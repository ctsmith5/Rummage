package handlers

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type FavoriteHandler struct {
	favoriteService services.FavoriteService
}

func NewFavoriteHandler(favoriteService services.FavoriteService) *FavoriteHandler {
	return &FavoriteHandler{
		favoriteService: favoriteService,
	}
}

func (h *FavoriteHandler) AddFavorite(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	saleID := chi.URLParam(r, "saleId")

	favorite, err := h.favoriteService.AddFavorite(userID, saleID)
	if err != nil {
		if err == services.ErrAlreadyFavorited {
			writeJSON(w, http.StatusConflict, models.NewErrorResponse("Sale already favorited"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to add favorite"))
		return
	}

	writeJSON(w, http.StatusCreated, models.NewSuccessResponse(favorite))
}

func (h *FavoriteHandler) RemoveFavorite(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	saleID := chi.URLParam(r, "saleId")

	err := h.favoriteService.RemoveFavorite(userID, saleID)
	if err != nil {
		if err == services.ErrFavoriteNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Favorite not found"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to remove favorite"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(map[string]string{"message": "Favorite removed successfully"}))
}

func (h *FavoriteHandler) ListFavorites(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	favorites, err := h.favoriteService.ListUserFavorites(userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to list favorites"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(favorites))
}

func (h *FavoriteHandler) ListFavoriteSales(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	sales, err := h.favoriteService.ListUserFavoriteSales(userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to list favorites"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sales))
}