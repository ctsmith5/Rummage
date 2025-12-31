package services

import (
	"errors"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
)

var (
	ErrFavoriteNotFound = errors.New("favorite not found")
	ErrAlreadyFavorited = errors.New("sale already favorited")
)

type FavoriteService struct {
	mu           sync.RWMutex
	favorites    map[string]*models.Favorite // favoriteID -> favorite
	userFavorites map[string]map[string]string // userID -> saleID -> favoriteID
	salesService *SalesService
}

func NewFavoriteService() *FavoriteService {
	return &FavoriteService{
		favorites:     make(map[string]*models.Favorite),
		userFavorites: make(map[string]map[string]string),
	}
}

func (s *FavoriteService) SetSalesService(salesService *SalesService) {
	s.salesService = salesService
}

func (s *FavoriteService) AddFavorite(userID, saleID string) (*models.Favorite, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Check if already favorited
	if userFavs, exists := s.userFavorites[userID]; exists {
		if _, exists := userFavs[saleID]; exists {
			return nil, ErrAlreadyFavorited
		}
	}

	favorite := &models.Favorite{
		ID:        uuid.New().String(),
		UserID:    userID,
		SaleID:    saleID,
		CreatedAt: time.Now(),
	}

	s.favorites[favorite.ID] = favorite

	// Update user favorites map
	if s.userFavorites[userID] == nil {
		s.userFavorites[userID] = make(map[string]string)
	}
	s.userFavorites[userID][saleID] = favorite.ID

	return favorite, nil
}

func (s *FavoriteService) RemoveFavorite(userID, saleID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	userFavs, exists := s.userFavorites[userID]
	if !exists {
		return ErrFavoriteNotFound
	}

	favoriteID, exists := userFavs[saleID]
	if !exists {
		return ErrFavoriteNotFound
	}

	delete(s.favorites, favoriteID)
	delete(s.userFavorites[userID], saleID)

	return nil
}

func (s *FavoriteService) ListUserFavorites(userID string) ([]*models.Favorite, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var favorites []*models.Favorite

	userFavs, exists := s.userFavorites[userID]
	if !exists {
		return favorites, nil
	}

	for _, favoriteID := range userFavs {
		if fav, exists := s.favorites[favoriteID]; exists {
			favorites = append(favorites, fav)
		}
	}

	return favorites, nil
}

func (s *FavoriteService) IsFavorited(userID, saleID string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()

	userFavs, exists := s.userFavorites[userID]
	if !exists {
		return false
	}

	_, exists = userFavs[saleID]
	return exists
}

