package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/storage"
)

// ErrImageRejected is returned when SafeSearch flags an image as unsafe.
var ErrImageRejected = errors.New("image rejected: violates community guidelines")

// ModerationResult holds the outcome of a successful moderation pass.
type ModerationResult struct {
	ApprovedURL string
}

// ModerationService runs Vision SafeSearch on images in Firebase Storage and
// promotes safe ones from pending/ to approved paths inline (synchronously).
type ModerationService struct {
	gcs     *storage.Client
	bucket  string
	flagSvc *MongoUserFlagService
}

// NewModerationService creates a storage client once at server startup.
// flagSvc may be nil if strike tracking is not needed.
func NewModerationService(ctx context.Context, bucket string, flagSvc *MongoUserFlagService) (*ModerationService, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("moderation: storage client: %w", err)
	}
	return &ModerationService{
		gcs:     client,
		bucket:  bucket,
		flagSvc: flagSvc,
	}, nil
}

// ModerateAndPromote runs SafeSearch on a pending/ path. If safe, promotes
// (copy to final path, delete pending, return download URL). If unsafe, deletes
// the pending object, records a strike, and returns ErrImageRejected.
func (m *ModerationService) ModerateAndPromote(ctx context.Context, pendingPath, userID string) (*ModerationResult, error) {
	if !strings.HasPrefix(pendingPath, "pending/") {
		// Already approved — nothing to do.
		return &ModerationResult{ApprovedURL: pendingPath}, nil
	}

	gcsURI := fmt.Sprintf("gs://%s/%s", m.bucket, pendingPath)
	log.Printf("[moderation] running SafeSearch on %s", gcsURI)

	ss, err := DetectSafeSearch(ctx, gcsURI)
	if err != nil {
		log.Printf("[moderation] SafeSearch error path=%s err=%v", pendingPath, err)
		return nil, fmt.Errorf("moderation: safesearch: %w", err)
	}

	log.Printf("[moderation] SafeSearch result for %s: adult=%s violence=%s racy=%s isUnsafe=%v",
		pendingPath, ss.Adult, ss.Violence, ss.Racy, ss.IsUnsafe())

	if ss.IsUnsafe() {
		log.Printf("[moderation] image UNSAFE — deleting %s", pendingPath)
		if err := m.deleteObject(ctx, pendingPath); err != nil {
			log.Printf("[moderation] delete failed path=%s err=%v", pendingPath, err)
		}
		if m.flagSvc != nil && userID != "" {
			if _, err := m.flagSvc.AddStrike(ctx, userID); err != nil {
				log.Printf("[moderation] strike failed userID=%s err=%v", userID, err)
			}
		}
		return nil, ErrImageRejected
	}

	// Safe — promote.
	finalName := strings.TrimPrefix(pendingPath, "pending/")
	token := newToken()
	approvedURL := firebaseDownloadURL(m.bucket, finalName, token)

	log.Printf("[moderation] image SAFE — promoting %s -> %s", pendingPath, finalName)
	if err := m.promoteObject(ctx, pendingPath, finalName, token); err != nil {
		return nil, fmt.Errorf("moderation: promote: %w", err)
	}

	return &ModerationResult{ApprovedURL: approvedURL}, nil
}

// ModerateMultiple moderates a list of image URLs. Already-approved URLs are
// passed through. Pending URLs are moderated inline. Returns approved URLs
// and any error (first rejection stops processing).
func (m *ModerationService) ModerateMultiple(ctx context.Context, paths []string, userID string) ([]string, error) {
	approved := make([]string, 0, len(paths))
	for _, p := range paths {
		if strings.TrimSpace(p) == "" {
			continue
		}
		if !strings.HasPrefix(p, "pending/") {
			approved = append(approved, p)
			continue
		}
		res, err := m.ModerateAndPromote(ctx, p, userID)
		if err != nil {
			return nil, err
		}
		approved = append(approved, res.ApprovedURL)
	}
	return approved, nil
}

func (m *ModerationService) promoteObject(ctx context.Context, from, to, token string) error {
	b := m.gcs.Bucket(m.bucket)
	src := b.Object(from)
	dst := b.Object(to)

	// Read source metadata with retry for eventual consistency.
	// Firebase Storage may need a moment to finalize uploads before the object is accessible.
	var attrs *storage.ObjectAttrs
	var err error
	maxRetries := 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		attrs, err = src.Attrs(ctx)
		if err == nil {
			break
		}
		// If object not found and we have retries left, wait and try again.
		if err == storage.ErrObjectNotExist && attempt < maxRetries-1 {
			backoff := time.Duration(attempt+1) * 500 * time.Millisecond
			log.Printf("[moderation] object not found yet, retrying in %v (attempt %d/%d): %s", backoff, attempt+1, maxRetries, from)
			time.Sleep(backoff)
			continue
		}
		return fmt.Errorf("source attrs: %w", err)
	}

	md := map[string]string{}
	for k, v := range attrs.Metadata {
		md[k] = v
	}
	md["moderation"] = "approved"
	md["firebaseStorageDownloadTokens"] = token

	if _, err := dst.CopierFrom(src).Run(ctx); err != nil {
		return fmt.Errorf("copy: %w", err)
	}
	if _, err := dst.Update(ctx, storage.ObjectAttrsToUpdate{Metadata: md}); err != nil {
		return fmt.Errorf("update metadata: %w", err)
	}
	return src.Delete(ctx)
}

func (m *ModerationService) deleteObject(ctx context.Context, name string) error {
	return m.gcs.Bucket(m.bucket).Object(name).Delete(ctx)
}

func newToken() string {
	return fmt.Sprintf("%d-%d", time.Now().UnixNano(), os.Getpid())
}

func firebaseDownloadURL(bucket, objectName, token string) string {
	return fmt.Sprintf(
		"https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
		bucket,
		url.PathEscape(objectName),
		url.QueryEscape(token),
	)
}
