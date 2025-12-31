package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type AuthHandler struct {
	userService   *services.UserService
	jwtSecret     string
	jwtExpiration time.Duration
}

func NewAuthHandler(userService *services.UserService, jwtSecret string, jwtExpiration time.Duration) *AuthHandler {
	return &AuthHandler{
		userService:   userService,
		jwtSecret:     jwtSecret,
		jwtExpiration: jwtExpiration,
	}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req models.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	if errors := req.Validate(); len(errors) > 0 {
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	user, err := h.userService.Register(&req)
	if err != nil {
		if err == services.ErrEmailExists {
			writeJSON(w, http.StatusConflict, models.NewErrorResponse("Email already registered"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to create user"))
		return
	}

	token, err := h.generateToken(user.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to generate token"))
		return
	}

	writeJSON(w, http.StatusCreated, models.NewSuccessResponse(models.AuthResponse{
		Token: token,
		User:  *user,
	}))
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	if errors := req.Validate(); len(errors) > 0 {
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	user, err := h.userService.Login(&req)
	if err != nil {
		if err == services.ErrUserNotFound || err == services.ErrInvalidPassword {
			writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid email or password"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Login failed"))
		return
	}

	token, err := h.generateToken(user.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to generate token"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(models.AuthResponse{
		Token: token,
		User:  *user,
	}))
}

func (h *AuthHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	user, err := h.userService.GetByID(userID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, models.NewErrorResponse("User not found"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(user))
}

func (h *AuthHandler) generateToken(userID string) (string, error) {
	claims := jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(h.jwtExpiration).Unix(),
		"iat":     time.Now().Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.jwtSecret))
}

