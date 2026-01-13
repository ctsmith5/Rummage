package services

import (
	"context"
	"crypto/tls"
	"log"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/rummage/backend/internal/models"
)

type MongoSalesService struct {
	client    *mongo.Client
	db        *mongo.Database
	salesColl *mongo.Collection
	itemsColl *mongo.Collection
}

type mongoGeoPoint struct {
	Type        string    `bson:"type"`
	Coordinates []float64 `bson:"coordinates"` // [lng, lat]
}

type mongoSaleDoc struct {
	ID             string        `bson:"_id"`
	UserID         string        `bson:"user_id"`
	Title          string        `bson:"title"`
	Description    string        `bson:"description"`
	Address        string        `bson:"address"`
	SaleCoverPhoto string        `bson:"sale_cover_photo,omitempty"`
	Latitude       float64       `bson:"latitude"`
	Longitude      float64       `bson:"longitude"`
	StartDate      time.Time     `bson:"start_date"`
	EndDate        time.Time     `bson:"end_date"`
	IsActive       bool          `bson:"is_active"`
	CreatedAt      time.Time     `bson:"created_at"`
	Location       mongoGeoPoint `bson:"location"`
}

type mongoItemDoc struct {
	ID             string    `bson:"_id"`
	SaleID         string    `bson:"sale_id"`
	Name           string    `bson:"name"`
	Description    string    `bson:"description"`
	Price          float64   `bson:"price"`
	ImageURLs      []string  `bson:"image_urls,omitempty"`
	LegacyImageURL string    `bson:"image_url,omitempty"`
	Category       string    `bson:"category"`
	CreatedAt      time.Time `bson:"created_at"`
}

func NewMongoSalesService(ctx context.Context, mongoURI, dbName string) (*MongoSalesService, error) {
	// Atlas occasionally fails TLS negotiation in some environments unless we force TLS 1.2.
	// Evidence (Cloud Run): "remote error: tls: internal error" during server selection.
	tlsCfg := &tls.Config{
		MinVersion: tls.VersionTLS12,
		MaxVersion: tls.VersionTLS12,
	}

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI).SetTLSConfig(tlsCfg))
	if err != nil {
		return nil, err
	}
	if err := client.Ping(ctx, nil); err != nil {
		return nil, err
	}

	db := client.Database(dbName)
	sales := db.Collection("sales")
	items := db.Collection("items")

	svc := &MongoSalesService{
		client:    client,
		db:        db,
		salesColl: sales,
		itemsColl: items,
	}

	// Best-effort indexes.
	_, _ = sales.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "created_at", Value: -1}}},
		{Keys: bson.D{{Key: "user_id", Value: 1}}},
		{Keys: bson.D{{Key: "latitude", Value: 1}, {Key: "longitude", Value: 1}}},
		{Keys: bson.D{{Key: "location", Value: "2dsphere"}}},
		{Keys: bson.D{{Key: "title", Value: "text"}, {Key: "description", Value: "text"}, {Key: "address", Value: "text"}}},
	})
	_, _ = items.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "sale_id", Value: 1}}},
		{Keys: bson.D{{Key: "created_at", Value: -1}}},
	})

	log.Printf("MongoDB connected: db=%s", dbName)
	return svc, nil
}

func (s *MongoSalesService) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func saleDocToModel(d mongoSaleDoc) *models.GarageSale {
	return &models.GarageSale{
		ID:             d.ID,
		UserID:         d.UserID,
		Title:          d.Title,
		Description:    d.Description,
		Address:        d.Address,
		SaleCoverPhoto: d.SaleCoverPhoto,
		Latitude:       d.Latitude,
		Longitude:      d.Longitude,
		StartDate:      d.StartDate,
		EndDate:        d.EndDate,
		IsActive:       d.IsActive,
		Items:          []models.Item{},
		CreatedAt:      d.CreatedAt,
	}
}

func itemDocToModel(d mongoItemDoc) *models.Item {
	imgs := d.ImageURLs
	if len(imgs) == 0 && d.LegacyImageURL != "" {
		imgs = []string{d.LegacyImageURL}
	}
	return &models.Item{
		ID:          d.ID,
		SaleID:      d.SaleID,
		Name:        d.Name,
		Description: d.Description,
		Price:       d.Price,
		ImageURLs:   imgs,
		Category:    d.Category,
		CreatedAt:   d.CreatedAt,
	}
}

func (s *MongoSalesService) Create(userID string, req *models.CreateSaleRequest) (*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	id := uuid.New().String()
	now := time.Now().UTC()

	doc := mongoSaleDoc{
		ID:             id,
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
		CreatedAt:      now,
		Location: mongoGeoPoint{
			Type:        "Point",
			Coordinates: []float64{req.Longitude, req.Latitude},
		},
	}

	if _, err := s.salesColl.InsertOne(ctx, doc); err != nil {
		return nil, err
	}

	return saleDocToModel(doc), nil
}

func (s *MongoSalesService) GetByID(id string) (*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var sale mongoSaleDoc
	if err := s.salesColl.FindOne(ctx, bson.M{"_id": id}).Decode(&sale); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, ErrSaleNotFound
		}
		return nil, err
	}

	items, err := s.getItemsForSales(ctx, []string{id})
	if err != nil {
		return nil, err
	}

	m := saleDocToModel(sale)
	if list, ok := items[id]; ok {
		m.Items = list
	}
	return m, nil
}

func (s *MongoSalesService) Update(userID, saleID string, req *models.UpdateSaleRequest) (*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"title":       req.Title,
			"description": req.Description,
			"address":     req.Address,
			"latitude":    req.Latitude,
			"longitude":   req.Longitude,
			"start_date":  req.StartDate,
			"end_date":    req.EndDate,
			"location": bson.M{
				"type":        "Point",
				"coordinates": []float64{req.Longitude, req.Latitude},
			},
		},
	}

	res := s.salesColl.FindOneAndUpdate(
		ctx,
		bson.M{"_id": saleID, "user_id": userID},
		update,
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)

	var updated mongoSaleDoc
	if err := res.Decode(&updated); err != nil {
		if err == mongo.ErrNoDocuments {
			// Distinguish not found vs unauthorized.
			var exists mongoSaleDoc
			if err2 := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&exists); err2 == mongo.ErrNoDocuments {
				return nil, ErrSaleNotFound
			}
			return nil, ErrUnauthorized
		}
		return nil, err
	}

	items, err := s.getItemsForSales(ctx, []string{saleID})
	if err != nil {
		return nil, err
	}
	m := saleDocToModel(updated)
	if list, ok := items[saleID]; ok {
		m.Items = list
	}
	return m, nil
}

func (s *MongoSalesService) SetSaleCoverPhoto(userID, saleID, coverURL string) (*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"sale_cover_photo": coverURL,
		},
	}

	res := s.salesColl.FindOneAndUpdate(
		ctx,
		bson.M{"_id": saleID, "user_id": userID},
		update,
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)

	var updated mongoSaleDoc
	if err := res.Decode(&updated); err != nil {
		if err == mongo.ErrNoDocuments {
			// Distinguish not found vs unauthorized.
			var exists mongoSaleDoc
			if err2 := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&exists); err2 == mongo.ErrNoDocuments {
				return nil, ErrSaleNotFound
			}
			return nil, ErrUnauthorized
		}
		return nil, err
	}

	items, err := s.getItemsForSales(ctx, []string{saleID})
	if err != nil {
		return nil, err
	}
	m := saleDocToModel(updated)
	if list, ok := items[saleID]; ok {
		m.Items = list
	}
	return m, nil
}

func (s *MongoSalesService) Delete(userID, saleID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Ensure ownership.
	var sale mongoSaleDoc
	if err := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&sale); err != nil {
		if err == mongo.ErrNoDocuments {
			return ErrSaleNotFound
		}
		return err
	}
	if sale.UserID != userID {
		return ErrUnauthorized
	}

	if _, err := s.itemsColl.DeleteMany(ctx, bson.M{"sale_id": saleID}); err != nil {
		return err
	}
	if _, err := s.salesColl.DeleteOne(ctx, bson.M{"_id": saleID}); err != nil {
		return err
	}
	return nil
}

func (s *MongoSalesService) StartSale(userID, saleID string) (*models.GarageSale, error) {
	return s.setActive(userID, saleID, true)
}

func (s *MongoSalesService) EndSale(userID, saleID string) (*models.GarageSale, error) {
	return s.setActive(userID, saleID, false)
}

func (s *MongoSalesService) setActive(userID, saleID string, active bool) (*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	res := s.salesColl.FindOneAndUpdate(
		ctx,
		bson.M{"_id": saleID, "user_id": userID},
		bson.M{"$set": bson.M{"is_active": active}},
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)

	var updated mongoSaleDoc
	if err := res.Decode(&updated); err != nil {
		if err == mongo.ErrNoDocuments {
			var exists mongoSaleDoc
			if err2 := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&exists); err2 == mongo.ErrNoDocuments {
				return nil, ErrSaleNotFound
			}
			return nil, ErrUnauthorized
		}
		return nil, err
	}

	items, err := s.getItemsForSales(ctx, []string{saleID})
	if err != nil {
		return nil, err
	}
	m := saleDocToModel(updated)
	if list, ok := items[saleID]; ok {
		m.Items = list
	}
	return m, nil
}

func (s *MongoSalesService) ListByBounds(minLat, maxLat, minLng, maxLng float64, limit int) ([]*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if limit <= 0 {
		limit = 500
	}
	if limit > 500 {
		limit = 500
	}

	filter := bson.M{
		"latitude":  bson.M{"$gte": minLat, "$lte": maxLat},
		"longitude": bson.M{"$gte": minLng, "$lte": maxLng},
	}

	cur, err := s.salesColl.Find(
		ctx,
		filter,
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(int64(limit)),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(ctx)

	saleDocs := make([]mongoSaleDoc, 0)
	saleIDs := make([]string, 0)
	for cur.Next(ctx) {
		var d mongoSaleDoc
		if err := cur.Decode(&d); err != nil {
			return nil, err
		}
		saleDocs = append(saleDocs, d)
		saleIDs = append(saleIDs, d.ID)
	}
	if err := cur.Err(); err != nil {
		return nil, err
	}

	results := make([]*models.GarageSale, 0, len(saleDocs))
	if len(saleDocs) == 0 {
		return results, nil
	}

	itemsBySale, err := s.getItemsForSales(ctx, saleIDs)
	if err != nil {
		return nil, err
	}

	for _, d := range saleDocs {
		m := saleDocToModel(d)
		if items, ok := itemsBySale[d.ID]; ok {
			m.Items = items
		}
		results = append(results, m)
	}
	return results, nil
}

func (s *MongoSalesService) ListNearby(lat, lng, radiusMi float64) ([]*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if radiusMi <= 0 {
		radiusMi = 10
	}
	// Mongo expects radians for $centerSphere.
	radians := radiusMi / 3959.0

	filter := bson.M{
		"location": bson.M{
			"$geoWithin": bson.M{
				"$centerSphere": bson.A{
					bson.A{lng, lat},
					radians,
				},
			},
		},
	}

	cur, err := s.salesColl.Find(
		ctx,
		filter,
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(500),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(ctx)

	saleDocs := make([]mongoSaleDoc, 0)
	saleIDs := make([]string, 0)
	for cur.Next(ctx) {
		var d mongoSaleDoc
		if err := cur.Decode(&d); err != nil {
			return nil, err
		}
		saleDocs = append(saleDocs, d)
		saleIDs = append(saleIDs, d.ID)
	}
	if err := cur.Err(); err != nil {
		return nil, err
	}

	results := make([]*models.GarageSale, 0, len(saleDocs))
	if len(saleDocs) == 0 {
		return results, nil
	}

	itemsBySale, err := s.getItemsForSales(ctx, saleIDs)
	if err != nil {
		return nil, err
	}

	for _, d := range saleDocs {
		m := saleDocToModel(d)
		if items, ok := itemsBySale[d.ID]; ok {
			m.Items = items
		}
		results = append(results, m)
	}

	// As a safety, sort newest first in-memory too.
	sort.Slice(results, func(i, j int) bool {
		return results[i].CreatedAt.After(results[j].CreatedAt)
	})

	return results, nil
}

func (s *MongoSalesService) SearchNearby(lat, lng, radiusMi float64, q string) ([]*models.GarageSale, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if radiusMi <= 0 {
		radiusMi = 10
	}
	q = strings.TrimSpace(q)
	if q == "" {
		return []*models.GarageSale{}, nil
	}

	// Mongo expects radians for $centerSphere.
	radians := radiusMi / 3959.0

	filter := bson.M{
		"$and": bson.A{
			bson.M{
				"location": bson.M{
					"$geoWithin": bson.M{
						"$centerSphere": bson.A{
							bson.A{lng, lat},
							radians,
						},
					},
				},
			},
			bson.M{
				"$text": bson.M{"$search": q},
			},
		},
	}

	cur, err := s.salesColl.Find(
		ctx,
		filter,
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(500),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(ctx)

	saleDocs := make([]mongoSaleDoc, 0)
	saleIDs := make([]string, 0)
	for cur.Next(ctx) {
		var d mongoSaleDoc
		if err := cur.Decode(&d); err != nil {
			return nil, err
		}
		saleDocs = append(saleDocs, d)
		saleIDs = append(saleIDs, d.ID)
	}
	if err := cur.Err(); err != nil {
		return nil, err
	}

	results := make([]*models.GarageSale, 0, len(saleDocs))
	if len(saleDocs) == 0 {
		return results, nil
	}

	itemsBySale, err := s.getItemsForSales(ctx, saleIDs)
	if err != nil {
		return nil, err
	}

	for _, d := range saleDocs {
		m := saleDocToModel(d)
		if items, ok := itemsBySale[d.ID]; ok {
			m.Items = items
		}
		results = append(results, m)
	}
	return results, nil
}

func (s *MongoSalesService) AddItem(userID, saleID string, req *models.CreateItemRequest) (*models.Item, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Ensure sale exists + ownership.
	var sale mongoSaleDoc
	if err := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&sale); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, ErrSaleNotFound
		}
		return nil, err
	}
	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	id := uuid.New().String()
	now := time.Now().UTC()
	imgs := req.ImageURLs
	if imgs == nil {
		imgs = []string{}
	}
	doc := mongoItemDoc{
		ID:          id,
		SaleID:      saleID,
		Name:        req.Name,
		Description: req.Description,
		Price:       req.Price,
		ImageURLs:   imgs,
		Category:    req.Category,
		CreatedAt:   now,
	}

	if _, err := s.itemsColl.InsertOne(ctx, doc); err != nil {
		return nil, err
	}

	return itemDocToModel(doc), nil
}

func (s *MongoSalesService) UpdateItem(userID, saleID, itemID string, req *models.UpdateItemRequest) (*models.Item, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Ensure sale exists + ownership.
	var sale mongoSaleDoc
	if err := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&sale); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, ErrSaleNotFound
		}
		return nil, err
	}
	if sale.UserID != userID {
		return nil, ErrUnauthorized
	}

	imgs := req.ImageURLs
	if imgs == nil {
		imgs = []string{}
	}

	update := bson.M{
		"$set": bson.M{
			"name":        req.Name,
			"description": req.Description,
			"price":       req.Price,
			"category":    req.Category,
			"image_urls":  imgs,
		},
	}

	res := s.itemsColl.FindOneAndUpdate(
		ctx,
		bson.M{"_id": itemID, "sale_id": saleID},
		update,
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)

	var updated mongoItemDoc
	if err := res.Decode(&updated); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, ErrItemNotFound
		}
		return nil, err
	}

	return itemDocToModel(updated), nil
}

func (s *MongoSalesService) DeleteItem(userID, saleID, itemID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Ensure sale exists + ownership.
	var sale mongoSaleDoc
	if err := s.salesColl.FindOne(ctx, bson.M{"_id": saleID}).Decode(&sale); err != nil {
		if err == mongo.ErrNoDocuments {
			return ErrSaleNotFound
		}
		return err
	}
	if sale.UserID != userID {
		return ErrUnauthorized
	}

	res, err := s.itemsColl.DeleteOne(ctx, bson.M{"_id": itemID, "sale_id": saleID})
	if err != nil {
		return err
	}
	if res.DeletedCount == 0 {
		return ErrItemNotFound
	}
	return nil
}

func (s *MongoSalesService) getItemsForSales(ctx context.Context, saleIDs []string) (map[string][]models.Item, error) {
	if len(saleIDs) == 0 {
		return map[string][]models.Item{}, nil
	}

	cur, err := s.itemsColl.Find(
		ctx,
		bson.M{"sale_id": bson.M{"$in": saleIDs}},
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(ctx)

	out := make(map[string][]models.Item)
	for cur.Next(ctx) {
		var d mongoItemDoc
		if err := cur.Decode(&d); err != nil {
			return nil, err
		}
		out[d.SaleID] = append(out[d.SaleID], *itemDocToModel(d))
	}
	if err := cur.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
