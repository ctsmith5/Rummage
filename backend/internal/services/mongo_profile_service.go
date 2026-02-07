package services

import (
	"context"
	"crypto/tls"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/rummage/backend/internal/models"
)

var defaultDOB = time.Date(1970, 1, 1, 0, 0, 0, 0, time.UTC)

type MongoProfileService struct {
	client      *mongo.Client
	db          *mongo.Database
	profilesCol *mongo.Collection
}

func NewMongoProfileService(ctx context.Context, mongoURI, dbName string) (*MongoProfileService, error) {
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
	col := db.Collection("profiles")

	// Best-effort indexes.
	_, _ = col.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "user_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	})

	return &MongoProfileService{
		client:      client,
		db:          db,
		profilesCol: col,
	}, nil
}

func (s *MongoProfileService) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func (s *MongoProfileService) GetByUserID(ctx context.Context, userID string) (*models.Profile, error) {
	var prof models.Profile
	if err := s.profilesCol.FindOne(ctx, bson.M{"user_id": userID}).Decode(&prof); err != nil {
		return nil, err
	}
	if prof.DOB.IsZero() {
		prof.DOB = defaultDOB
	}
	return &prof, nil
}

// GetOrCreate returns the user's profile. If missing, it creates one with default DOB.
// Also ensures DOB is non-zero for legacy/test accounts by backfilling 1970-01-01.
func (s *MongoProfileService) GetOrCreate(ctx context.Context, userID string, email string) (*models.Profile, error) {
	now := time.Now()

	var prof models.Profile
	err := s.profilesCol.FindOne(ctx, bson.M{"user_id": userID}).Decode(&prof)
	if err == nil {
		if email != "" && prof.Email == "" {
			_, _ = s.profilesCol.UpdateOne(ctx, bson.M{"user_id": userID}, bson.M{
				"$set": bson.M{"email": email, "updated_at": now},
			})
			prof.Email = email
			prof.UpdatedAt = now
		}
		if prof.DOB.IsZero() {
			// Backfill legacy missing DOB.
			_, _ = s.profilesCol.UpdateOne(ctx, bson.M{"user_id": userID}, bson.M{
				"$set": bson.M{"dob": defaultDOB, "updated_at": now},
			})
			prof.DOB = defaultDOB
			prof.UpdatedAt = now
		}
		return &prof, nil
	}
	if err != mongo.ErrNoDocuments {
		return nil, err
	}

	prof = models.Profile{
		UserID:    userID,
		Email:     email,
		DOB:       defaultDOB,
		UpdatedAt: now,
	}
	_, err = s.profilesCol.InsertOne(ctx, prof)
	if err != nil {
		// If a race created it, fetch again.
		var retry models.Profile
		if err2 := s.profilesCol.FindOne(ctx, bson.M{"user_id": userID}).Decode(&retry); err2 == nil {
			if retry.DOB.IsZero() {
				retry.DOB = defaultDOB
			}
			return &retry, nil
		}
		return nil, err
	}
	return &prof, nil
}

func (s *MongoProfileService) Upsert(ctx context.Context, userID string, email string, req *models.UpsertProfileRequest) (*models.Profile, error) {
	now := time.Now()

	set := bson.M{
		"updated_at": now,
	}
	if email != "" {
		set["email"] = email
	}
	if req.DisplayName != nil {
		set["display_name"] = *req.DisplayName
	}
	if req.Bio != nil {
		set["bio"] = *req.Bio
	}
	if req.PhotoURL != nil {
		set["photo_url"] = *req.PhotoURL
	}
	if req.DOB != nil {
		set["dob"] = *req.DOB
	}

	// Ensure the document exists and DOB is never null.
	setOnInsert := bson.M{
		"user_id": userID,
	}
	// IMPORTANT: MongoDB forbids updating the same path in both $set and $setOnInsert.
	// Only provide a default DOB on insert when the caller is NOT explicitly setting DOB.
	// Email is always set via $set to stay in sync with Firebase Auth.
	if req.DOB == nil {
		setOnInsert["dob"] = defaultDOB
	}

	_, err := s.profilesCol.UpdateOne(
		ctx,
		bson.M{"user_id": userID},
		bson.M{"$set": set, "$setOnInsert": setOnInsert},
		options.Update().SetUpsert(true),
	)
	if err != nil {
		return nil, err
	}

	var prof models.Profile
	if err := s.profilesCol.FindOne(ctx, bson.M{"user_id": userID}).Decode(&prof); err != nil {
		return nil, err
	}
	if prof.DOB.IsZero() {
		// Backfill if something inserted without dob (shouldn't happen).
		_, _ = s.profilesCol.UpdateOne(ctx, bson.M{"user_id": userID}, bson.M{
			"$set": bson.M{"dob": defaultDOB, "updated_at": now},
		})
		prof.DOB = defaultDOB
		prof.UpdatedAt = now
	}
	return &prof, nil
}

// ApprovePendingProfilePhoto updates any profile whose photo_url currently equals pendingPath
// to point at the final approved download URL.
func (s *MongoProfileService) ApprovePendingProfilePhoto(ctx context.Context, pendingPath string, approvedURL string) error {
	if strings.TrimSpace(pendingPath) == "" || strings.TrimSpace(approvedURL) == "" {
		return nil
	}
	now := time.Now()
	_, err := s.profilesCol.UpdateOne(ctx, bson.M{"photo_url": pendingPath}, bson.M{
		"$set": bson.M{"photo_url": approvedURL, "updated_at": now},
	})
	return err
}

// RejectPendingProfilePhoto clears photo_url if it matches pendingPath.
func (s *MongoProfileService) RejectPendingProfilePhoto(ctx context.Context, pendingPath string) error {
	if strings.TrimSpace(pendingPath) == "" {
		return nil
	}
	now := time.Now()
	_, err := s.profilesCol.UpdateOne(ctx, bson.M{"photo_url": pendingPath}, bson.M{
		"$set": bson.M{"photo_url": "", "updated_at": now},
	})
	return err
}

// ClearPhotoIfMatches clears photo_url if it matches the provided URL.
func (s *MongoProfileService) ClearPhotoIfMatches(ctx context.Context, userID string, url string) error {
	if userID == "" || url == "" {
		return nil
	}
	_, err := s.profilesCol.UpdateOne(ctx, bson.M{"user_id": userID, "photo_url": url}, bson.M{
		"$set": bson.M{"photo_url": ""},
	})
	return err
}
