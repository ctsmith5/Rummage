package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	fbauth "firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type ProfileHandler struct {
	profiles   *services.MongoProfileService
	authClient *fbauth.Client
}

func NewProfileHandler(profiles *services.MongoProfileService, authClient *fbauth.Client) *ProfileHandler {
	return &ProfileHandler{profiles: profiles, authClient: authClient}
}

func (h *ProfileHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}
	email := middleware.GetUserEmail(r.Context())

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prof, err := h.profiles.GetOrCreate(ctx, userID, email)
	if err != nil {
		log.Printf("[GetProfile] user=%s error=%v", userID, err)
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to load profile"))
		return
	}
	writeJSON(w, http.StatusOK, models.NewSuccessResponse(prof))
}

func (h *ProfileHandler) UpsertProfile(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}
	email := middleware.GetUserEmail(r.Context())

	var req models.UpsertProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	// Enforce 16+ (defense-in-depth). 1970 default is fine.
	if req.DOB != nil {
		dob := *req.DOB
		if dob.After(time.Now()) {
			writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("DOB cannot be in the future"))
			return
		}
		now := time.Now().UTC()
		cutoff := time.Date(now.Year()-16, now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
		d := dob.UTC()
		if d.After(cutoff) {
			writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("User must be 16 years old or older"))
			return
		}
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prof, err := h.profiles.Upsert(ctx, userID, email, &req)
	if err != nil {
		log.Printf("[UpsertProfile] user=%s error=%v", userID, err)
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to update profile"))
		return
	}
	writeJSON(w, http.StatusOK, models.NewSuccessResponse(prof))
}

// GetPublicProfileByUserID returns a public-safe profile for the requested userId (no DOB).
func (h *ProfileHandler) GetPublicProfileByUserID(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	targetID := chi.URLParam(r, "userId")
	if targetID == "" {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Missing userId"))
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prof, err := h.profiles.GetByUserID(ctx, targetID)
	if err != nil {
		// Fallback: if no Mongo profile exists yet, try Firebase Auth user record.
		if h.authClient == nil {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Profile not found"))
			return
		}
		u, err2 := h.authClient.GetUser(ctx, targetID)
		if err2 != nil {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Profile not found"))
			return
		}
		pub := models.PublicProfile{
			UserID:      targetID,
			Email:       u.Email,
			DisplayName: u.DisplayName,
			PhotoURL:    u.PhotoURL,
		}
		writeJSON(w, http.StatusOK, models.NewSuccessResponse(pub))
		return
	}

	pub := models.PublicProfile{
		UserID:      prof.UserID,
		Email:       prof.Email,
		DisplayName: prof.DisplayName,
		PhotoURL:    prof.PhotoURL,
	}

	// Best-effort fill missing fields from Firebase Auth.
	if h.authClient != nil && (pub.Email == "" || pub.DisplayName == "" || pub.PhotoURL == "") {
		if u, err2 := h.authClient.GetUser(ctx, targetID); err2 == nil {
			if pub.Email == "" {
				pub.Email = u.Email
			}
			if pub.DisplayName == "" {
				pub.DisplayName = u.DisplayName
			}
			if pub.PhotoURL == "" {
				pub.PhotoURL = u.PhotoURL
			}
		}
	}
	writeJSON(w, http.StatusOK, models.NewSuccessResponse(pub))
}
