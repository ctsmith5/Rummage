package services

import (
	"errors"

	"github.com/rummage/backend/internal/models"
)

var (
	ErrFavoriteNotFound = errors.New("favorite not found")
	ErrAlreadyFavorited = errors.New("sale already favorited")
	ErrFavoriteBadInput = errors.New("bad input")
	ErrFavoriteSaleGone = errors.New("sale not found")
)

// FavoriteService is used by handlers; production uses Mongo-backed implementation.
type FavoriteService interface {
	AddFavorite(userID, saleID string) (*models.Favorite, error)
	RemoveFavorite(userID, saleID string) error
	ListUserFavorites(userID string) ([]*models.Favorite, error)
	// ListUserFavoriteSales returns full sale objects (most-recent favorited first).
	ListUserFavoriteSales(userID string) ([]*models.GarageSale, error)
}
