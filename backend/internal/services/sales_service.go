package services

import (
	"errors"
	"log"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/storage"
)

var (
	ErrSaleNotFound = errors.New("sale not found")
	ErrItemNotFound = errors.New("item not found")
	ErrUnauthorized = errors.New("unauthorized to modify this sale")
)

// SalesService is the interface used by handlers. Implementations may be file-based
// (local dev) or backed by a real database (production).
type SalesService interface {
	Create(userID string, req *models.CreateSaleRequest) (*models.GarageSale, error)
	GetByID(id string) (*models.GarageSale, error)
	Update(userID, saleID string, req *models.UpdateSaleRequest) (*models.GarageSale, error)
	SetSaleCoverPhoto(userID, saleID, coverURL string) (*models.GarageSale, error)
	Delete(userID, saleID string) error
	StartSale(userID, saleID string) (*models.GarageSale, error)
	EndSale(userID, saleID string) (*models.GarageSale, error)
	ListNearby(lat, lng, radiusMi float64) ([]*models.GarageSale, error)
	SearchNearby(lat, lng, radiusMi float64, q string) ([]*models.GarageSale, error)
	ListByBounds(minLat, maxLat, minLng, maxLng float64, limit int) ([]*models.GarageSale, error)
	AddItem(userID, saleID string, req *models.CreateItemRequest) (*models.Item, error)
	UpdateItem(userID, saleID, itemID string, req *models.UpdateItemRequest) (*models.Item, error)
	DeleteItem(userID, saleID, itemID string) error
}

// SalesData represents the persisted sales data structure
type SalesData struct {
	Sales map[string]*models.GarageSale `json:"sales"`
	Items map[string]*models.Item       `json:"items"`
}

type FileSalesService struct {
	mu    sync.RWMutex
	sales map[string]*models.GarageSale
	items map[string]*models.Item
	store *storage.JSONStore
}

func NewFileSalesService(dataDir string) *FileSalesService {
	store, err := storage.NewJSONStore(dataDir, "sales.json")
	if err != nil {
		log.Printf("Warning: Failed to create sales store: %v", err)
	}

	svc := &FileSalesService{
		sales: make(map[string]*models.GarageSale),
		items: make(map[string]*models.Item),
		store: store,
	}

	// Load existing data
	if store != nil {
		svc.loadFromStore()
	}

	return svc
}

func (s *FileSalesService) loadFromStore() {
	var data SalesData
	if err := s.store.Load(&data); err != nil {
		log.Printf("Warning: Failed to load sales from store: %v", err)
		return
	}

	if data.Sales != nil {
		s.sales = data.Sales
	}
	if data.Items != nil {
		s.items = data.Items
	}

	log.Printf("Loaded %d sales and %d items from persistent storage", len(s.sales), len(s.items))
}

func (s *FileSalesService) saveToStore() {
	if s.store == nil {
		return
	}

	data := SalesData{
		Sales: s.sales,
		Items: s.items,
	}

	if err := s.store.Save(data); err != nil {
		log.Printf("Warning: Failed to save sales to store: %v", err)
	}
}

func (s *FileSalesService) Create(userID string, req *models.CreateSaleRequest) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale := &models.GarageSale{
		ID:             uuid.New().String(),
		UserID:         userID,
		Title:          req.Title,
		Description:    req.Description,
		Address:        req.Address,
		SaleCoverPhoto: "",
		Latitude:       req.Latitude,
		Longitude:      req.Longitude,
		StartDate:      req.StartDate,
		EndDate:        req.EndDate,
		IsActive:       false,
		Items:          []models.Item{},
		CreatedAt:      time.Now(),
	}

	s.sales[sale.ID] = sale
	s.saveToStore()
	return sale, nil
}

func (s *FileSalesService) GetByID(id string) (*models.GarageSale, error) {
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

func (s *FileSalesService) Update(userID, saleID string, req *models.UpdateSaleRequest) (*models.GarageSale, error) {
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

	s.saveToStore()
	return sale, nil
}

func (s *FileSalesService) SetSaleCoverPhoto(userID, saleID, coverURL string) (*models.GarageSale, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}
	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	sale.SaleCoverPhoto = coverURL
	s.saveToStore()
	return sale, nil
}

func (s *FileSalesService) Delete(userID, saleID string) error {
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
	s.saveToStore()
	return nil
}

func (s *FileSalesService) StartSale(userID, saleID string) (*models.GarageSale, error) {
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
	s.saveToStore()
	return sale, nil
}

func (s *FileSalesService) EndSale(userID, saleID string) (*models.GarageSale, error) {
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
	s.saveToStore()
	return sale, nil
}

func (s *FileSalesService) ListNearby(lat, lng, radiusMi float64) ([]*models.GarageSale, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	results := make([]*models.GarageSale, 0)

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

func (s *FileSalesService) SearchNearby(lat, lng, radiusMi float64, q string) ([]*models.GarageSale, error) {
	// File-based store is only for local/dev. Implement a simple in-memory filter
	// that roughly matches the Mongo search endpoint behavior.
	s.mu.RLock()
	defer s.mu.RUnlock()

	if radiusMi <= 0 {
		radiusMi = 10
	}
	q = strings.ToLower(strings.TrimSpace(q))

	results := make([]*models.GarageSale, 0)
	for _, sale := range s.sales {
		distance := haversineDistance(lat, lng, sale.Latitude, sale.Longitude)
		if distance > radiusMi {
			continue
		}

		if q != "" {
			blob := strings.ToLower(sale.Title + " " + sale.Description + " " + sale.Address)
			if !strings.Contains(blob, q) {
				continue
			}
		}

		saleCopy := *sale
		saleCopy.Items = s.getItemsForSale(sale.ID)
		results = append(results, &saleCopy)
	}

	// Newest first, to match other endpoints.
	sort.Slice(results, func(i, j int) bool {
		return results[i].CreatedAt.After(results[j].CreatedAt)
	})
	return results, nil
}

// ListByBounds returns all sales within a geographic bounding box
func (s *FileSalesService) ListByBounds(minLat, maxLat, minLng, maxLng float64, limit int) ([]*models.GarageSale, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	results := make([]*models.GarageSale, 0)

	for _, sale := range s.sales {
		if sale.Latitude >= minLat && sale.Latitude <= maxLat &&
			sale.Longitude >= minLng && sale.Longitude <= maxLng {
			saleCopy := *sale
			saleCopy.Items = s.getItemsForSale(sale.ID)
			results = append(results, &saleCopy)
		}
	}

	// Stable ordering so a cap returns consistent results.
	sort.Slice(results, func(i, j int) bool {
		return results[i].CreatedAt.After(results[j].CreatedAt)
	})

	if limit > 0 && len(results) > limit {
		results = results[:limit]
	}

	return results, nil
}

func (s *FileSalesService) AddItem(userID, saleID string, req *models.CreateItemRequest) (*models.Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}

	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	imgs := req.ImageURLs
	if imgs == nil {
		imgs = []string{}
	}

	item := &models.Item{
		ID:          uuid.New().String(),
		SaleID:      saleID,
		Name:        req.Name,
		Description: req.Description,
		Price:       req.Price,
		ImageURLs:   imgs,
		Category:    req.Category,
		CreatedAt:   time.Now(),
	}

	s.items[item.ID] = item
	s.saveToStore()
	return item, nil
}

func (s *FileSalesService) UpdateItem(userID, saleID, itemID string, req *models.UpdateItemRequest) (*models.Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, exists := s.sales[saleID]
	if !exists {
		return nil, ErrSaleNotFound
	}
	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	item, exists := s.items[itemID]
	if !exists || item.SaleID != saleID {
		return nil, ErrItemNotFound
	}

	imgs := req.ImageURLs
	if imgs == nil {
		imgs = []string{}
	}

	item.Name = req.Name
	item.Description = req.Description
	item.Price = req.Price
	item.Category = req.Category
	item.ImageURLs = imgs

	s.saveToStore()
	return item, nil
}

func (s *FileSalesService) DeleteItem(userID, saleID, itemID string) error {
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
	s.saveToStore()
	return nil
}

func (s *FileSalesService) getItemsForSale(saleID string) []models.Item {
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
