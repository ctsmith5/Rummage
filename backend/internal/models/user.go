package models

import (
	"time"
)

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Name         string    `json:"name"`
	CreatedAt    time.Time `json:"created_at"`
}

type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Name     string `json:"name"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

func (r *RegisterRequest) Validate() map[string]string {
	errors := make(map[string]string)

	if r.Email == "" {
		errors["email"] = "Email is required"
	}
	if r.Password == "" {
		errors["password"] = "Password is required"
	} else if len(r.Password) < 6 {
		errors["password"] = "Password must be at least 6 characters"
	}
	if r.Name == "" {
		errors["name"] = "Name is required"
	}

	return errors
}

func (r *LoginRequest) Validate() map[string]string {
	errors := make(map[string]string)

	if r.Email == "" {
		errors["email"] = "Email is required"
	}
	if r.Password == "" {
		errors["password"] = "Password is required"
	}

	return errors
}

