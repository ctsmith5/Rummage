package models

import "time"

// UserFlag tracks moderation outcomes for a user.
type UserFlag struct {
	UserID       string    `json:"user_id" bson:"user_id"`
	Strikes      int       `json:"strikes" bson:"strikes"`
	LastStrikeAt time.Time `json:"last_strike_at" bson:"last_strike_at"`
	UpdatedAt    time.Time `json:"updated_at" bson:"updated_at"`
}

