package models

import "time"

// Profile is user-editable profile data stored in Mongo and keyed by Firebase UID.
type Profile struct {
	UserID      string    `json:"user_id" bson:"user_id"`
	Email       string    `json:"email" bson:"email,omitempty"`
	DisplayName string    `json:"display_name" bson:"display_name,omitempty"`
	Bio         string    `json:"bio" bson:"bio,omitempty"`
	DOB         time.Time `json:"dob" bson:"dob"`
	PhotoURL    string    `json:"photo_url" bson:"photo_url,omitempty"`
	UpdatedAt   time.Time `json:"updated_at" bson:"updated_at"`
}

// PublicProfile is safe to share with other authenticated users (no DOB).
type PublicProfile struct {
	UserID      string `json:"user_id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	PhotoURL    string `json:"photo_url"`
}

type UpsertProfileRequest struct {
	DisplayName *string `json:"display_name"`
	Bio         *string `json:"bio"`
	// DOB is required for new profiles. For updates, if omitted the existing DOB is preserved.
	DOB      *time.Time `json:"dob"`
	PhotoURL *string    `json:"photo_url"`
}

