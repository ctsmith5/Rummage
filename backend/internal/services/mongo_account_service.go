package services

import (
	"context"
	"crypto/tls"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type MongoAccountService struct {
	client       *mongo.Client
	db           *mongo.Database
	salesCol     *mongo.Collection
	itemsCol     *mongo.Collection
	favoritesCol *mongo.Collection
	profilesCol  *mongo.Collection
}

func NewMongoAccountService(ctx context.Context, mongoURI, dbName string) (*MongoAccountService, error) {
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
	return &MongoAccountService{
		client:       client,
		db:           db,
		salesCol:     db.Collection("sales"),
		itemsCol:     db.Collection("items"),
		favoritesCol: db.Collection("favorites"),
		profilesCol:  db.Collection("profiles"),
	}, nil
}

func (s *MongoAccountService) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

type DeleteAccountResult struct {
	ImageURLs []string `json:"image_urls"`
	SaleIDs   []string `json:"sale_ids"`
}

// DeleteAccount deletes all data associated with the given Firebase UID:
// - profile doc
// - favorites by user_id
// - sales by user_id and their items
// - favorites pointing at those sales (by sale_id)
// It returns Firebase image URLs (sale cover, item images, profile photo) to be deleted client-side.
func (s *MongoAccountService) DeleteAccount(ctx context.Context, userID string) (*DeleteAccountResult, error) {
	// Gather image URLs.
	urls := make(map[string]struct{})

	// profile.photo_url
	{
		var prof struct {
			PhotoURL string `bson:"photo_url"`
		}
		if err := s.profilesCol.FindOne(ctx, bson.M{"user_id": userID}).Decode(&prof); err == nil {
			if prof.PhotoURL != "" {
				urls[prof.PhotoURL] = struct{}{}
			}
		}
	}

	// sales + sale cover urls
	type saleDoc struct {
		ID             string `bson:"_id"`
		SaleCoverPhoto string `bson:"sale_cover_photo"`
	}
	saleIDs := make([]string, 0)
	{
		cur, err := s.salesCol.Find(ctx, bson.M{"user_id": userID}, options.Find().SetProjection(bson.M{
			"_id":             1,
			"sale_cover_photo": 1,
		}))
		if err != nil {
			return nil, err
		}
		defer cur.Close(ctx)

		for cur.Next(ctx) {
			var d saleDoc
			if err := cur.Decode(&d); err != nil {
				return nil, err
			}
			saleIDs = append(saleIDs, d.ID)
			if d.SaleCoverPhoto != "" {
				urls[d.SaleCoverPhoto] = struct{}{}
			}
		}
		if err := cur.Err(); err != nil {
			return nil, err
		}
	}

	// items image urls for the user's sales
	if len(saleIDs) > 0 {
		type itemDoc struct {
			ImageURLs      []string `bson:"image_urls"`
			LegacyImageURL string   `bson:"image_url"`
		}
		cur, err := s.itemsCol.Find(ctx, bson.M{"sale_id": bson.M{"$in": saleIDs}}, options.Find().SetProjection(bson.M{
			"image_urls": 1,
			"image_url":  1,
		}))
		if err != nil {
			return nil, err
		}
		defer cur.Close(ctx)

		for cur.Next(ctx) {
			var d itemDoc
			if err := cur.Decode(&d); err != nil {
				return nil, err
			}
			for _, u := range d.ImageURLs {
				if u != "" {
					urls[u] = struct{}{}
				}
			}
			if d.LegacyImageURL != "" {
				urls[d.LegacyImageURL] = struct{}{}
			}
		}
		if err := cur.Err(); err != nil {
			return nil, err
		}
	}

	// Deletes (order matters a bit to avoid leaving dangling pointers)
	// 1) favorites by user_id OR favorites pointing at sale ids being removed
	if len(saleIDs) > 0 {
		_, _ = s.favoritesCol.DeleteMany(ctx, bson.M{
			"$or": []bson.M{
				{"user_id": userID},
				{"sale_id": bson.M{"$in": saleIDs}},
			},
		})
	} else {
		_, _ = s.favoritesCol.DeleteMany(ctx, bson.M{"user_id": userID})
	}

	// 2) items for those sales
	if len(saleIDs) > 0 {
		_, _ = s.itemsCol.DeleteMany(ctx, bson.M{"sale_id": bson.M{"$in": saleIDs}})
	}

	// 3) sales by user
	_, _ = s.salesCol.DeleteMany(ctx, bson.M{"user_id": userID})

	// 4) profile
	_, _ = s.profilesCol.DeleteOne(ctx, bson.M{"user_id": userID})

	// Deduped list
	out := make([]string, 0, len(urls))
	for u := range urls {
		out = append(out, u)
	}

	return &DeleteAccountResult{
		ImageURLs: out,
		SaleIDs:   saleIDs,
	}, nil
}

// Helper for handlers that want a sane timeout.
func DefaultAccountTimeout() time.Duration { return 20 * time.Second }

