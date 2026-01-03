package services

import (
	"errors"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/storage"
)

var (
	ErrFavoriteNotFound = errors.New("favorite not found")
	ErrAlreadyFavorited = errors.New("sale already favorited")
)

// FavoriteData represents the persisted favorites data structure
type FavoriteData struct {
	Favorites     map[string]*models.Favorite   `json:"favorites"`
	UserFavorites map[string]map[string]string `json:"user_favorites"`
}

type FavoriteService struct {
	mu            sync.RWMutex
	favorites     map[string]*models.Favorite
	userFavorites map[string]map[string]string
	salesService  *SalesService
	store         *storage.JSONStore
}

func NewFavoriteService(dataDir string) *FavoriteService {
	store, err := storage.NewJSONStore(dataDir, "favorites.json")
	if err != nil {
		log.Printf("Warning: Failed to create favorites store: %v", err)
	}

	svc := &FavoriteService{
		favorites:     make(map[string]*models.Favorite),
		userFavorites: make(map[string]map[string]string),
		store:         store,
	}

	// Load existing data
	if store != nil {
		svc.loadFromStore()
	}

	return svc
}

func (s *FavoriteService) loadFromStore() {
	var data FavoriteData
	if err := s.store.Load(&data); err != nil {
		log.Printf("Warning: Failed to load favorites from store: %v", err)
		return
	}

	if data.Favorites != nil {
		s.favorites = data.Favorites
	}
	if data.UserFavorites != nil {
		s.userFavorites = data.UserFavorites
	}

	log.Printf("Loaded %d favorites from persistent storage", len(s.favorites))
}

func (s *FavoriteService) saveToStore() {
	if s.store == nil {
		return
	}

	data := FavoriteData{
		Favorites:     s.favorites,
		UserFavorites: s.userFavorites,
	}

	if err := s.store.Save(data); err != nil {
		log.Printf("Warning: Failed to save favorites to store: %v", err)
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

	s.saveToStore()
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

	s.saveToStore()
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

