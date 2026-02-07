package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"github.com/rummage/backend/internal/services"
	"go.mongodb.org/mongo-driver/mongo"
)

// Eventarc delivers CloudEvents; for GCS finalized events the body contains object info.
// Minimal fields we need: bucket, name, metadata.
type gcsFinalizeEvent struct {
	Bucket   string            `json:"bucket"`
	Name     string            `json:"name"`
	Metadata map[string]string `json:"metadata"`
}

// cloudEventEnvelope handles Eventarc structured content mode where the GCS
// payload is nested inside a "data" field.
type cloudEventEnvelope struct {
	Data gcsFinalizeEvent `json:"data"`
}

func main() {
	addr := getEnv("PORT", "8080")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/events", handleFinalize)

	log.Printf("moderation-worker listening on :%s", addr)
	log.Fatal(http.ListenAndServe(":"+addr, nil))
}

func handleFinalize(w http.ResponseWriter, r *http.Request) {
	// Only accept POSTs from Eventarc.
	if r.Method != http.MethodPost {
		log.Printf("[worker] rejected non-POST method=%s", r.Method)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Log Eventarc/CloudEvent headers for diagnostics.
	ceType := r.Header.Get("Ce-Type")
	ceSource := r.Header.Get("Ce-Source")
	ceSubject := r.Header.Get("Ce-Subject")
	contentType := r.Header.Get("Content-Type")
	log.Printf("[worker] event received: Ce-Type=%s Ce-Source=%s Ce-Subject=%s Content-Type=%s",
		ceType, ceSource, ceSubject, contentType)

	// Read raw body so we can log it and attempt multiple parse strategies.
	rawBody, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("[worker] failed to read request body: %v", err)
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	log.Printf("[worker] raw event body (%d bytes): %s", len(rawBody), string(rawBody))

	// Try to decode as a direct GCS notification (binary content mode).
	var ev gcsFinalizeEvent
	if err := json.Unmarshal(rawBody, &ev); err != nil {
		log.Printf("[worker] failed to decode event body: %v", err)
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	// If bucket/name are empty, the event may be wrapped in a CloudEvent envelope
	// (structured content mode) with the GCS data nested under "data".
	if ev.Bucket == "" || ev.Name == "" {
		log.Printf("[worker] top-level bucket/name empty, trying CloudEvent envelope parse")
		var envelope cloudEventEnvelope
		if err := json.Unmarshal(rawBody, &envelope); err == nil && envelope.Data.Bucket != "" && envelope.Data.Name != "" {
			ev = envelope.Data
			log.Printf("[worker] successfully parsed from CloudEvent envelope: bucket=%s name=%s", ev.Bucket, ev.Name)
		} else {
			log.Printf("[worker] CloudEvent envelope parse also failed or empty: bucket=%q name=%q err=%v",
				envelope.Data.Bucket, envelope.Data.Name, err)
		}
	}

	log.Printf("[worker] parsed event: bucket=%s name=%s metadata=%v", ev.Bucket, ev.Name, ev.Metadata)

	// Only process pending uploads.
	if ev.Bucket == "" || ev.Name == "" {
		log.Printf("[worker] skipping event: bucket or name is empty after all parse attempts")
		w.WriteHeader(http.StatusOK)
		return
	}
	if !strings.HasPrefix(ev.Name, "pending/") {
		log.Printf("[worker] skipping non-pending object: name=%s", ev.Name)
		w.WriteHeader(http.StatusOK)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()

	gcsURI := fmt.Sprintf("gs://%s/%s", ev.Bucket, ev.Name)
	log.Printf("[worker] running SafeSearch on %s", gcsURI)

	// If metadata was not in the event payload, fetch it directly from GCS.
	if ev.Metadata == nil || (ev.Metadata["userId"] == "" && ev.Metadata["type"] == "") {
		log.Printf("[worker] metadata missing from event payload, fetching from GCS object attrs")
		if fetchedMeta, err := fetchGCSObjectMetadata(ctx, ev.Bucket, ev.Name); err != nil {
			log.Printf("[worker] failed to fetch GCS object metadata: %v", err)
		} else {
			ev.Metadata = fetchedMeta
			log.Printf("[worker] fetched GCS metadata: %v", ev.Metadata)
		}
	}

	ss, err := services.DetectSafeSearch(ctx, gcsURI)
	if err != nil {
		log.Printf("[worker] safesearch error bucket=%s name=%s err=%v", ev.Bucket, ev.Name, err)
		// Retry by returning 500; Eventarc will retry.
		http.Error(w, "safesearch failed", http.StatusInternalServerError)
		return
	}

	log.Printf("[worker] safesearch result for %s: adult=%s violence=%s racy=%s spoof=%s medical=%s isUnsafe=%v",
		ev.Name, ss.Adult, ss.Violence, ss.Racy, ss.Spoof, ss.Medical, ss.IsUnsafe())

	// Connect to Mongo services used for strike/clear and for eventual approvals (later).
	mongoURI := os.Getenv("MONGO_URI")
	mongoDB := getEnv("MONGO_DB", "rummage")
	if mongoURI == "" {
		log.Printf("[worker] MONGO_URI env var is not set")
		http.Error(w, "MONGO_URI missing", http.StatusInternalServerError)
		return
	}

	log.Printf("[worker] connecting to MongoDB (db=%s)", mongoDB)

	// Reuse existing services for updates.
	salesSvc, err := services.NewMongoSalesService(ctx, mongoURI, mongoDB)
	if err != nil {
		log.Printf("[worker] mongo sales service init failed: %v", err)
		http.Error(w, "mongo sales init failed", http.StatusInternalServerError)
		return
	}
	defer salesSvc.Close(ctx)

	profSvc, err := services.NewMongoProfileService(ctx, mongoURI, mongoDB)
	if err != nil {
		log.Printf("[worker] mongo profile service init failed: %v", err)
		http.Error(w, "mongo profile init failed", http.StatusInternalServerError)
		return
	}
	defer profSvc.Close(ctx)

	flagSvc, err := services.NewMongoUserFlagService(ctx, mongoURI, mongoDB)
	if err != nil {
		log.Printf("[worker] mongo user_flags service init failed: %v", err)
		http.Error(w, "mongo user_flags init failed", http.StatusInternalServerError)
		return
	}
	defer flagSvc.Close(ctx)

	log.Printf("[worker] MongoDB services connected successfully")

	userID := ""
	typ := ""
	if ev.Metadata != nil {
		userID = ev.Metadata["userId"]
		typ = ev.Metadata["type"]
	}
	log.Printf("[worker] extracted metadata: userID=%s type=%s", userID, typ)

	if userID == "" {
		log.Printf("[worker] WARNING: userID is empty — Mongo lookups by pending path may still work but strikes cannot be recorded")
	}
	if typ == "" {
		log.Printf("[worker] WARNING: type is empty — cannot determine which Mongo collection to update")
	}

	// Unsafe: delete object and clear references + strike.
	if ss.IsUnsafe() {
		log.Printf("[worker] image UNSAFE — deleting object and clearing references: bucket=%s name=%s userID=%s type=%s",
			ev.Bucket, ev.Name, userID, typ)

		if err := deleteGCSObject(ctx, ev.Bucket, ev.Name); err != nil {
			log.Printf("[worker] delete object failed bucket=%s name=%s err=%v", ev.Bucket, ev.Name, err)
			http.Error(w, "delete failed", http.StatusInternalServerError)
			return
		}
		log.Printf("[worker] deleted unsafe object from GCS: %s", ev.Name)

		// Clear pending references + strike.
		if userID != "" {
			if _, err := flagSvc.AddStrike(ctx, userID); err != nil {
				log.Printf("[worker] failed to add strike for userID=%s: %v", userID, err)
			} else {
				log.Printf("[worker] strike recorded for userID=%s", userID)
			}
		}
		switch typ {
		case "sale_cover":
			if err := salesSvc.RejectPendingSaleCover(ctx, ev.Name); err != nil {
				log.Printf("[worker] RejectPendingSaleCover failed for path=%s: %v", ev.Name, err)
			} else {
				log.Printf("[worker] rejected pending sale cover: path=%s", ev.Name)
			}
		case "sale_item":
			if err := salesSvc.RejectPendingItemImage(ctx, ev.Name); err != nil {
				log.Printf("[worker] RejectPendingItemImage failed for path=%s: %v", ev.Name, err)
			} else {
				log.Printf("[worker] rejected pending item image: path=%s", ev.Name)
			}
		case "profile_photo":
			if err := profSvc.RejectPendingProfilePhoto(ctx, ev.Name); err != nil {
				log.Printf("[worker] RejectPendingProfilePhoto failed for path=%s: %v", ev.Name, err)
			} else {
				log.Printf("[worker] rejected pending profile photo: path=%s", ev.Name)
			}
		default:
			log.Printf("[worker] WARNING: unknown type=%q for unsafe image, no Mongo references cleared", typ)
		}

		log.Printf("[worker] DONE (unsafe): name=%s", ev.Name)
		w.WriteHeader(http.StatusOK)
		return
	}

	// Safe: promote to approved path (strip pending/) and set moderation=approved.
	finalName := strings.TrimPrefix(ev.Name, "pending/")
	token := newToken()
	approvedURL := firebaseDownloadURL(ev.Bucket, finalName, token)

	log.Printf("[worker] image SAFE — promoting: from=%s to=%s approvedURL=%s", ev.Name, finalName, approvedURL)

	if err := promoteObject(ctx, ev.Bucket, ev.Name, finalName, ev.Metadata, token); err != nil {
		log.Printf("[worker] promote failed bucket=%s from=%s to=%s err=%v", ev.Bucket, ev.Name, finalName, err)
		http.Error(w, "promote failed", http.StatusInternalServerError)
		return
	}
	log.Printf("[worker] object promoted successfully in GCS: %s -> %s", ev.Name, finalName)

	// Update Mongo to point to the approved download URL.
	switch typ {
	case "sale_cover":
		if err := salesSvc.ApprovePendingSaleCover(ctx, ev.Name, approvedURL); err != nil {
			log.Printf("[worker] ApprovePendingSaleCover failed for path=%s: %v", ev.Name, err)
		} else {
			log.Printf("[worker] approved sale cover: pendingPath=%s approvedURL=%s", ev.Name, approvedURL)
		}
	case "sale_item":
		if err := salesSvc.ApprovePendingItemImage(ctx, ev.Name, approvedURL); err != nil {
			log.Printf("[worker] ApprovePendingItemImage failed for path=%s: %v", ev.Name, err)
		} else {
			log.Printf("[worker] approved item image: pendingPath=%s approvedURL=%s", ev.Name, approvedURL)
		}
	case "profile_photo":
		if err := profSvc.ApprovePendingProfilePhoto(ctx, ev.Name, approvedURL); err != nil {
			log.Printf("[worker] ApprovePendingProfilePhoto failed for path=%s: %v", ev.Name, err)
		} else {
			log.Printf("[worker] approved profile photo: pendingPath=%s approvedURL=%s", ev.Name, approvedURL)
		}
	default:
		log.Printf("[worker] WARNING: unknown type=%q for safe image, no Mongo references updated", typ)
	}

	log.Printf("[worker] DONE (safe): name=%s approvedURL=%s", ev.Name, approvedURL)
	w.WriteHeader(http.StatusOK)
}

func fetchGCSObjectMetadata(ctx context.Context, bucket, name string) (map[string]string, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("storage client: %w", err)
	}
	defer client.Close()

	attrs, err := client.Bucket(bucket).Object(name).Attrs(ctx)
	if err != nil {
		return nil, fmt.Errorf("object attrs: %w", err)
	}
	return attrs.Metadata, nil
}

func deleteGCSObject(ctx context.Context, bucket, name string) error {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer client.Close()
	return client.Bucket(bucket).Object(name).Delete(ctx)
}

func setGCSObjectMetadata(ctx context.Context, bucket, name string, md map[string]string) error {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer client.Close()

	obj := client.Bucket(bucket).Object(name)
	attrs, err := obj.Attrs(ctx)
	if err != nil {
		return err
	}
	next := map[string]string{}
	for k, v := range attrs.Metadata {
		next[k] = v
	}
	for k, v := range md {
		next[k] = v
	}
	_, err = obj.Update(ctx, storage.ObjectAttrsToUpdate{Metadata: next})
	return err
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// Avoid unused import errors when mongo driver errors bubble up differently in builds.
var _ = mongo.ErrNoDocuments

func newToken() string {
	// Firebase download token is an arbitrary string; UUID is fine.
	// Use time-based token to avoid adding new deps.
	return fmt.Sprintf("%d-%d", time.Now().UnixNano(), os.Getpid())
}

func firebaseDownloadURL(bucket string, objectName string, token string) string {
	// https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}
	return fmt.Sprintf(
		"https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
		bucket,
		url.PathEscape(objectName),
		url.QueryEscape(token),
	)
}

func promoteObject(ctx context.Context, bucket string, from string, to string, originalMeta map[string]string, token string) error {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer client.Close()

	b := client.Bucket(bucket)
	src := b.Object(from)
	dst := b.Object(to)

	// Copy and set metadata. Keep original metadata, ensure moderation=approved, add Firebase token.
	md := map[string]string{}
	for k, v := range originalMeta {
		md[k] = v
	}
	md["moderation"] = "approved"
	md["firebaseStorageDownloadTokens"] = token

	_, err = dst.CopierFrom(src).Run(ctx)
	if err != nil {
		return err
	}
	if _, err := dst.Update(ctx, storage.ObjectAttrsToUpdate{Metadata: md}); err != nil {
		return err
	}
	// Delete pending object.
	return src.Delete(ctx)
}
