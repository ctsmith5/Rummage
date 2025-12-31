package services

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
)

var (
	ErrImageNotFound = errors.New("image not found")
	ErrInvalidImage  = errors.New("invalid image file")
)

type ImageService struct {
	mu        sync.RWMutex
	uploadDir string
	images    map[string]*imageRecord // imageID -> image info
}

type imageRecord struct {
	ID       string
	Filename string
	Path     string
	UserID   string
}

func NewImageService(uploadDir string) *ImageService {
	// Create upload directory if it doesn't exist
	os.MkdirAll(uploadDir, 0755)

	return &ImageService{
		uploadDir: uploadDir,
		images:    make(map[string]*imageRecord),
	}
}

func (s *ImageService) Upload(userID string, filename string, file io.Reader) (*models.ImageUploadResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Generate unique ID for the image
	imageID := uuid.New().String()

	// Get file extension
	ext := filepath.Ext(filename)
	if ext == "" {
		ext = ".jpg"
	}

	// Create new filename
	newFilename := imageID + ext
	filePath := filepath.Join(s.uploadDir, newFilename)

	// Create the file
	dst, err := os.Create(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to create file: %w", err)
	}
	defer dst.Close()

	// Copy uploaded file to destination
	if _, err := io.Copy(dst, file); err != nil {
		os.Remove(filePath) // Clean up on error
		return nil, fmt.Errorf("failed to save file: %w", err)
	}

	// Store image record
	record := &imageRecord{
		ID:       imageID,
		Filename: newFilename,
		Path:     filePath,
		UserID:   userID,
	}
	s.images[imageID] = record

	return &models.ImageUploadResponse{
		ID:       imageID,
		URL:      "/uploads/" + newFilename,
		Filename: newFilename,
	}, nil
}

func (s *ImageService) Delete(userID, imageID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, exists := s.images[imageID]
	if !exists {
		return ErrImageNotFound
	}

	// Only allow the owner to delete
	if record.UserID != userID {
		return ErrUnauthorized
	}

	// Delete the file
	if err := os.Remove(record.Path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete file: %w", err)
	}

	delete(s.images, imageID)
	return nil
}

func (s *ImageService) GetByID(imageID string) (*imageRecord, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	record, exists := s.images[imageID]
	if !exists {
		return nil, ErrImageNotFound
	}

	return record, nil
}

