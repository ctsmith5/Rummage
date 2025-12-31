package services

import (
	"errors"
	"sync"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/rummage/backend/internal/models"
)

var (
	ErrUserNotFound     = errors.New("user not found")
	ErrEmailExists      = errors.New("email already registered")
	ErrInvalidPassword  = errors.New("invalid password")
)

type UserService struct {
	mu    sync.RWMutex
	users map[string]*models.User // In-memory storage (replace with DB later)
	byEmail map[string]string     // email -> userID mapping
}

func NewUserService() *UserService {
	return &UserService{
		users:   make(map[string]*models.User),
		byEmail: make(map[string]string),
	}
}

func (s *UserService) Register(req *models.RegisterRequest) (*models.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Check if email already exists
	if _, exists := s.byEmail[req.Email]; exists {
		return nil, ErrEmailExists
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &models.User{
		ID:           uuid.New().String(),
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Name:         req.Name,
		CreatedAt:    time.Now(),
	}

	s.users[user.ID] = user
	s.byEmail[user.Email] = user.ID

	return user, nil
}

func (s *UserService) Login(req *models.LoginRequest) (*models.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	userID, exists := s.byEmail[req.Email]
	if !exists {
		return nil, ErrUserNotFound
	}

	user := s.users[userID]
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, ErrInvalidPassword
	}

	return user, nil
}

func (s *UserService) GetByID(id string) (*models.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	user, exists := s.users[id]
	if !exists {
		return nil, ErrUserNotFound
	}

	return user, nil
}

