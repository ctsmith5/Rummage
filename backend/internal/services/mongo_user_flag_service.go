package services

import (
	"context"
	"crypto/tls"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/rummage/backend/internal/models"
)

type MongoUserFlagService struct {
	client *mongo.Client
	db     *mongo.Database
	col    *mongo.Collection
}

func NewMongoUserFlagService(ctx context.Context, mongoURI, dbName string) (*MongoUserFlagService, error) {
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
	col := db.Collection("user_flags")

	_, _ = col.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "user_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	})

	return &MongoUserFlagService{client: client, db: db, col: col}, nil
}

func (s *MongoUserFlagService) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

// AddStrike increments the strike counter for the user and returns the updated record.
func (s *MongoUserFlagService) AddStrike(ctx context.Context, userID string) (*models.UserFlag, error) {
	now := time.Now().UTC()
	update := bson.M{
		"$inc": bson.M{"strikes": 1},
		"$set": bson.M{"last_strike_at": now, "updated_at": now},
		"$setOnInsert": bson.M{
			"user_id":  userID,
			"strikes":  0,
			"updated_at": now,
		},
	}

	_, err := s.col.UpdateOne(ctx, bson.M{"user_id": userID}, update, options.Update().SetUpsert(true))
	if err != nil {
		return nil, err
	}

	var out models.UserFlag
	if err := s.col.FindOne(ctx, bson.M{"user_id": userID}).Decode(&out); err != nil {
		return nil, err
	}
	return &out, nil
}

