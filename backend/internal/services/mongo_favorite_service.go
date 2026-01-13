package services

import (
	"context"
	"crypto/tls"
	"log"
	"time"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/rummage/backend/internal/models"
)

type MongoFavoriteService struct {
	client       *mongo.Client
	db           *mongo.Database
	favoritesCol *mongo.Collection
	salesService SalesService
}

type mongoFavoriteDoc struct {
	ID        string    `bson:"_id"`
	UserID    string    `bson:"user_id"`
	SaleID    string    `bson:"sale_id"`
	CreatedAt time.Time `bson:"created_at"`
}

func NewMongoFavoriteService(
	ctx context.Context,
	mongoURI string,
	dbName string,
	salesService SalesService,
) (*MongoFavoriteService, error) {
	if mongoURI == "" || dbName == "" {
		return nil, ErrFavoriteBadInput
	}

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
	favs := db.Collection("favorites")

	svc := &MongoFavoriteService{
		client:       client,
		db:           db,
		favoritesCol: favs,
		salesService: salesService,
	}

	// Best-effort indexes.
	_, _ = favs.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "user_id", Value: 1}, {Key: "sale_id", Value: 1}},
			Options: options.Index().SetUnique(true),
		},
		{Keys: bson.D{{Key: "user_id", Value: 1}}},
		{Keys: bson.D{{Key: "created_at", Value: -1}}},
	})

	log.Printf("MongoDB connected (favorites): db=%s", dbName)
	return svc, nil
}

func (s *MongoFavoriteService) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func (s *MongoFavoriteService) AddFavorite(userID, saleID string) (*models.Favorite, error) {
	if userID == "" || saleID == "" {
		return nil, ErrFavoriteBadInput
	}

	// Ensure sale exists (also prevents favorites pointing to garbage IDs).
	if _, err := s.salesService.GetByID(saleID); err != nil {
		if err == ErrSaleNotFound {
			return nil, ErrFavoriteSaleGone
		}
		return nil, err
	}

	fav := &mongoFavoriteDoc{
		ID:        uuid.New().String(),
		UserID:    userID,
		SaleID:    saleID,
		CreatedAt: time.Now(),
	}

	_, err := s.favoritesCol.InsertOne(context.Background(), fav)
	if err != nil {
		// Duplicate key (already favorited).
		if mongo.IsDuplicateKeyError(err) {
			return nil, ErrAlreadyFavorited
		}
		return nil, err
	}

	return &models.Favorite{
		ID:        fav.ID,
		UserID:    fav.UserID,
		SaleID:    fav.SaleID,
		CreatedAt: fav.CreatedAt,
	}, nil
}

func (s *MongoFavoriteService) RemoveFavorite(userID, saleID string) error {
	if userID == "" || saleID == "" {
		return ErrFavoriteBadInput
	}

	res, err := s.favoritesCol.DeleteOne(context.Background(), bson.M{
		"user_id": userID,
		"sale_id": saleID,
	})
	if err != nil {
		return err
	}
	if res.DeletedCount == 0 {
		return ErrFavoriteNotFound
	}
	return nil
}

func (s *MongoFavoriteService) ListUserFavorites(userID string) ([]*models.Favorite, error) {
	if userID == "" {
		return nil, ErrFavoriteBadInput
	}

	cur, err := s.favoritesCol.Find(
		context.Background(),
		bson.M{"user_id": userID},
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(context.Background())

	out := make([]*models.Favorite, 0)
	for cur.Next(context.Background()) {
		var doc mongoFavoriteDoc
		if err := cur.Decode(&doc); err != nil {
			return nil, err
		}
		out = append(out, &models.Favorite{
			ID:        doc.ID,
			UserID:    doc.UserID,
			SaleID:    doc.SaleID,
			CreatedAt: doc.CreatedAt,
		})
	}
	return out, nil
}

func (s *MongoFavoriteService) ListUserFavoriteSales(userID string) ([]*models.GarageSale, error) {
	if userID == "" {
		return nil, ErrFavoriteBadInput
	}

	// Get favorites in order (most-recent first), then fetch each sale via SalesService
	// so we return full sale objects (including items).
	cur, err := s.favoritesCol.Find(
		context.Background(),
		bson.M{"user_id": userID},
		options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}),
	)
	if err != nil {
		return nil, err
	}
	defer cur.Close(context.Background())

	out := make([]*models.GarageSale, 0)
	for cur.Next(context.Background()) {
		var doc mongoFavoriteDoc
		if err := cur.Decode(&doc); err != nil {
			return nil, err
		}
		sale, err := s.salesService.GetByID(doc.SaleID)
		if err != nil {
			// Skip missing sales (deleted/inaccessible).
			if err == ErrSaleNotFound {
				continue
			}
			return nil, err
		}
		out = append(out, sale)
	}
	return out, nil
}
