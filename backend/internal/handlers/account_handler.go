package handlers

import (
	"context"
	"net/http"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type AccountHandler struct {
	accounts *services.MongoAccountService
}

func NewAccountHandler(accounts *services.MongoAccountService) *AccountHandler {
	return &AccountHandler{accounts: accounts}
}

// DeleteAccount deletes all backend data for the authenticated user and returns image URLs to delete
// from Firebase Storage client-side (best effort).
func (h *AccountHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), services.DefaultAccountTimeout())
	defer cancel()

	result, err := h.accounts.DeleteAccount(ctx, userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to delete account"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(result))
}

