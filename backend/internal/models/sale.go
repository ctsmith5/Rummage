package models

import (
	"time"
)

type GarageSale struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Address     string    `json:"address"`
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json:"longitude"`
	StartDate   time.Time `json:"start_date"`
	EndDate     time.Time `json:"end_date"`
	IsActive    bool      `json:"is_active"`
	Items       []Item    `json:"items,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateSaleRequest struct {
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Address     string    `json:"address"`
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json:"longitude"`
	StartDate   time.Time `json:"start_date"`
	EndDate     time.Time `json:"end_date"`
}

type UpdateSaleRequest struct {
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Address     string    `json:"address"`
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json:"longitude"`
	StartDate   time.Time `json:"start_date"`
	EndDate     time.Time `json:"end_date"`
}

type ListSalesQuery struct {
	Latitude  float64 `json:"lat"`
	Longitude float64 `json:"lng"`
	RadiusMi  float64 `json:"radius"` // Radius in miles
}

func (r *CreateSaleRequest) Validate() map[string]string {
	errors := make(map[string]string)

	if r.Title == "" {
		errors["title"] = "Title is required"
	}
	if r.Address == "" {
		errors["address"] = "Address is required"
	}
	if r.Latitude == 0 && r.Longitude == 0 {
		errors["location"] = "Location coordinates are required"
	}
	if r.StartDate.IsZero() {
		errors["start_date"] = "Start date is required"
	}
	if r.EndDate.IsZero() {
		errors["end_date"] = "End date is required"
	}
	if !r.EndDate.IsZero() && !r.StartDate.IsZero() && r.EndDate.Before(r.StartDate) {
		errors["end_date"] = "End date must be after start date"
	}

	return errors
}

