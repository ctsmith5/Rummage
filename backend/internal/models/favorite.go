package models

import (
	"time"
)

type Favorite struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	SaleID    string    `json:"sale_id"`
	CreatedAt time.Time `json:"created_at"`
}

type FavoriteWithSale struct {
	Favorite
	Sale GarageSale `json:"sale"`
}

