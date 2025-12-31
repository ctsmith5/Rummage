package handlers

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type ImageHandler struct {
	imageService *services.ImageService
	maxSizeMB    int64
}

func NewImageHandler(imageService *services.ImageService, maxSizeMB int64) *ImageHandler {
	return &ImageHandler{
		imageService: imageService,
		maxSizeMB:    maxSizeMB,
	}
}

func (h *ImageHandler) Upload(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	// Limit request body size
	r.Body = http.MaxBytesReader(w, r.Body, h.maxSizeMB*1024*1024)

	// Parse multipart form
	if err := r.ParseMultipartForm(h.maxSizeMB * 1024 * 1024); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("File too large or invalid form data"))
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("No image file provided"))
		return
	}
	defer file.Close()

	// Validate content type
	contentType := header.Header.Get("Content-Type")
	if !isValidImageType(contentType) {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid image type. Allowed: JPEG, PNG, GIF, WebP"))
		return
	}

	response, err := h.imageService.Upload(userID, header.Filename, file)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to upload image"))
		return
	}

	writeJSON(w, http.StatusCreated, models.NewSuccessResponse(response))
}

func (h *ImageHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	imageID := chi.URLParam(r, "imageId")

	err := h.imageService.Delete(userID, imageID)
	if err != nil {
		if err == services.ErrImageNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Image not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to delete this image"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to delete image"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(map[string]string{"message": "Image deleted successfully"}))
}

func isValidImageType(contentType string) bool {
	validTypes := map[string]bool{
		"image/jpeg": true,
		"image/jpg":  true,
		"image/png":  true,
		"image/gif":  true,
		"image/webp": true,
	}
	return validTypes[contentType]
}

