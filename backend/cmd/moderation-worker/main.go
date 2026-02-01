package main

import (
	"context"
	"encoding/json"
	"fmt"
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
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var ev gcsFinalizeEvent
	if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	// Only process pending uploads.
	if ev.Bucket == "" || ev.Name == "" || !strings.HasPrefix(ev.Name, "pending/") {
		w.WriteHeader(http.StatusOK)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()

	gcsURI := fmt.Sprintf("gs://%s/%s", ev.Bucket, ev.Name)

	ss, err := services.DetectSafeSearch(ctx, gcsURI)
	if err != nil {
		log.Printf("[worker] safesearch error bucket=%s name=%s err=%v", ev.Bucket, ev.Name, err)
		// Retry by returning 500; Eventarc will retry.
		http.Error(w, "safesearch failed", http.StatusInternalServerError)
		return
	}

	// Connect to Mongo services used for strike/clear and for eventual approvals (later).
	mongoURI := os.Getenv("MONGO_URI")
	mongoDB := getEnv("MONGO_DB", "rummage")
	if mongoURI == "" {
		http.Error(w, "MONGO_URI missing", http.StatusInternalServerError)
		return
	}

	// Reuse existing services for updates.
	salesSvc, err := services.NewMongoSalesService(ctx, mongoURI, mongoDB)
	if err != nil {
		http.Error(w, "mongo sales init failed", http.StatusInternalServerError)
		return
	}
	defer salesSvc.Close(ctx)

	profSvc, err := services.NewMongoProfileService(ctx, mongoURI, mongoDB)
	if err != nil {
		http.Error(w, "mongo profile init failed", http.StatusInternalServerError)
		return
	}
	defer profSvc.Close(ctx)

	flagSvc, err := services.NewMongoUserFlagService(ctx, mongoURI, mongoDB)
	if err != nil {
		http.Error(w, "mongo user_flags init failed", http.StatusInternalServerError)
		return
	}
	defer flagSvc.Close(ctx)

	userID := ""
	typ := ""
	if ev.Metadata != nil {
		userID = ev.Metadata["userId"]
		typ = ev.Metadata["type"]
	}

	// Unsafe: delete object and clear references + strike.
	if ss.IsUnsafe() {
		if err := deleteGCSObject(ctx, ev.Bucket, ev.Name); err != nil {
			log.Printf("[worker] delete object failed bucket=%s name=%s err=%v", ev.Bucket, ev.Name, err)
			http.Error(w, "delete failed", http.StatusInternalServerError)
			return
		}

		// Clear pending references + strike.
		if userID != "" {
			_, _ = flagSvc.AddStrike(ctx, userID)
		}
		switch typ {
		case "sale_cover":
			_ = salesSvc.RejectPendingSaleCover(ctx, ev.Name)
		case "sale_item":
			_ = salesSvc.RejectPendingItemImage(ctx, ev.Name)
		case "profile_photo":
			_ = profSvc.RejectPendingProfilePhoto(ctx, ev.Name)
		}

		w.WriteHeader(http.StatusOK)
		return
	}

	// Safe: promote to approved path (strip pending/) and set moderation=approved.
	finalName := strings.TrimPrefix(ev.Name, "pending/")
	token := newToken()
	approvedURL := firebaseDownloadURL(ev.Bucket, finalName, token)

	if err := promoteObject(ctx, ev.Bucket, ev.Name, finalName, ev.Metadata, token); err != nil {
		log.Printf("[worker] promote failed bucket=%s from=%s to=%s err=%v", ev.Bucket, ev.Name, finalName, err)
		http.Error(w, "promote failed", http.StatusInternalServerError)
		return
	}

	// Update Mongo to point to the approved download URL.
	switch typ {
	case "sale_cover":
		_ = salesSvc.ApprovePendingSaleCover(ctx, ev.Name, approvedURL)
	case "sale_item":
		_ = salesSvc.ApprovePendingItemImage(ctx, ev.Name, approvedURL)
	case "profile_photo":
		_ = profSvc.ApprovePendingProfilePhoto(ctx, ev.Name, approvedURL)
	}

	w.WriteHeader(http.StatusOK)
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
