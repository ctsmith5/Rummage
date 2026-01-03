package services

import (
	"errors"
	"math"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
)

var (
	ErrSaleNotFound = errors.New("sale not found")
	ErrItemNotFound = errors.New("item not found")
	ErrUnauthorized = errors.New("unauthorized to modify this sale")
)

type SalesService struct {
	mu    sync.RWMutex
	sales map[string]*models.GarageSale // In-memory storage (replace with DB later)
	items map[string]*models.Item       // itemID -> item
}

func NewSalesService() *SalesService {
	return &SalesService{
		sales: make(map[string]*models.GarageSale),
		items: make(map[string]*models.Item),
	}
}

func (s *SalesService) Create(userID string, req *models.CreateSaleRequest) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale := &models.GarageSale{
		ID:          uuid.New().String(),
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		Address:     req.Address,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
		StartDate:   req.StartDate,
		EndDate:     req.EndDate,
		IsActive:    false,
		Items:       []models.Item{},
		CreatedAt:   time.Now(),
	}

	s.sales[sale.ID] = sale
	return sale, nil
}

func (s *SalesService) GetByID(id string) (*models.GarageSale, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	sale, exists := s.sales[id]
	if !exists {
		return nil, ErrSaleNotFound
	}

	// Attach items
	saleCopy := *sale
	saleCopy.Items = s.getItemsForSale(id)

	return &saleCopy, nil
}

func (s *SalesService) Update(userID, saleID string, req *models.UpdateSaleRequest) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}

	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	sale.Title = req.Title
	sale.Description = req.Description
	sale.Address = req.Address
	sale.Latitude = req.Latitude
	sale.Longitude = req.Longitude
	sale.StartDate = req.StartDate
	sale.EndDate = req.EndDate

	return sale, nil
}

func (s *SalesService) Delete(userID, saleID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return ErrSaleNotFound
	}

	if sale.UserID != userID {
		return ErrUnauthorized
	}

	// Delete all items for this sale
	for itemID, item := range s.items {
		if item.SaleID == saleID {
			delete(s.items, itemID)
		}
	}

	delete(s.sales, saleID)
	return nil
}

func (s *SalesService) StartSale(userID, saleID string) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}

	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	sale.IsActive = true
	return sale, nil
}

func (s *SalesService) EndSale(userID, saleID string) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}

	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	sale.IsActive = false
	return sale, nil
}

func (s *SalesService) ListNearby(lat, lng, radiusMi float64) ([]*models.GarageSale, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []*models.GarageSale

	for _, sale := range s.sales {
		distance := haversineDistance(lat, lng, sale.Latitude, sale.Longitude)
		if distance <= radiusMi {
			saleCopy := *sale
			saleCopy.Items = s.getItemsForSale(sale.ID)
			results = append(results, &saleCopy)
		}
	}

	return results, nil
}

// ListByBounds returns all sales within a geographic bounding box
func (s *SalesService) ListByBounds(minLat, maxLat, minLng, maxLng float64) ([]*models.GarageSale, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []*models.GarageSale

	for _, sale := range s.sales {
		if sale.Latitude >= minLat && sale.Latitude <= maxLat &&
			sale.Longitude >= minLng && sale.Longitude <= maxLng {
			saleCopy := *sale
			saleCopy.Items = s.getItemsForSale(sale.ID)
			results = append(results, &saleCopy)
		}
	}

	return results, nil
}

func (s *SalesService) AddItem(userID, saleID string, req *models.CreateItemRequest) (*models.Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}

	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	item := &models.Item{
		ID:          uuid.New().String(),
		SaleID:      saleID,
		Name:        req.Name,
		Description: req.Description,
		Price:       req.Price,
		ImageURL:    req.ImageURL,
		Category:    req.Category,
		CreatedAt:   time.Now(),
	}

	s.items[item.ID] = item
	return item, nil
}

func (s *SalesService) DeleteItem(userID, saleID, itemID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return ErrSaleNotFound
	}

	if sale.UserID != userID {
		return ErrUnauthorized
	}

	item, exists := s.items[itemID]
	if !exists || item.SaleID != saleID {
		return ErrItemNotFound
	}

	delete(s.items, itemID)
	return nil
}

func (s *SalesService) getItemsForSale(saleID string) []models.Item {
	var items []models.Item
	for _, item := range s.items {
		if item.SaleID == saleID {
			items = append(items, *item)
		}
	}
	return items
}

// haversineDistance calculates distance between two points in miles
func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusMiles = 3959.0

	lat1Rad := lat1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	deltaLat := (lat2 - lat1) * math.Pi / 180
	deltaLon := (lon2 - lon1) * math.Pi / 180

	a := math.Sin(deltaLat/2)*math.Sin(deltaLat/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLon/2)*math.Sin(deltaLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusMiles * c
}

