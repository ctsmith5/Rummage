package models

import (
	"time"
)

type Item struct {
	ID          string    `json:"id"`
	SaleID      string    `json:"sale_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Price       float64   `json:"price"`
	ImageURL    string    `json:"image_url"`
	Category    string    `json:"category"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateItemRequest struct {
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	ImageURL    string  `json:"image_url"`
	Category    string  `json:"category"`
}

func (r *CreateItemRequest) Validate() map[string]string {
	errors := make(map[string]string)

	if r.Name == "" {
		errors["name"] = "Item name is required"
	}
	if r.Price < 0 {
		errors["price"] = "Price cannot be negative"
	}

	return errors
}

// Common item categories
var ItemCategories = []string{
	"Furniture",
	"Electronics",
	"Clothing",
	"Books",
	"Toys",
	"Kitchen",
	"Tools",
	"Sports",
	"Decor",
	"Antiques",
	"Other",
}

