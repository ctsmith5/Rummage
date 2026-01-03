package services

import (
	"errors"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/storage"
)

var (
	ErrUserNotFound    = errors.New("user not found")
	ErrEmailExists     = errors.New("email already registered")
	ErrInvalidPassword = errors.New("invalid password")
)

// UserData represents the persisted user data structure
type UserData struct {
	Users   map[string]*models.User `json:"users"`
	ByEmail map[string]string       `json:"by_email"`
}

type UserService struct {
	mu      sync.RWMutex
	users   map[string]*models.User
	byEmail map[string]string
	store   *storage.JSONStore
}

func NewUserService(dataDir string) *UserService {
	store, err := storage.NewJSONStore(dataDir, "users.json")
	if err != nil {
		log.Printf("Warning: Failed to create user store: %v", err)
	}

	svc := &UserService{
		users:   make(map[string]*models.User),
		byEmail: make(map[string]string),
		store:   store,
	}

	// Load existing data
	if store != nil {
		svc.loadFromStore()
	}

	return svc
}

func (s *UserService) loadFromStore() {
	var data UserData
	if err := s.store.Load(&data); err != nil {
		log.Printf("Warning: Failed to load users from store: %v", err)
		return
	}

	if data.Users != nil {
		s.users = data.Users
	}
	if data.ByEmail != nil {
		s.byEmail = data.ByEmail
	}

	log.Printf("Loaded %d users from persistent storage", len(s.users))
}

func (s *UserService) saveToStore() {
	if s.store == nil {
		return
	}

	data := UserData{
		Users:   s.users,
		ByEmail: s.byEmail,
	}

	if err := s.store.Save(data); err != nil {
		log.Printf("Warning: Failed to save users to store: %v", err)
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

	// Persist to storage
	s.saveToStore()

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

// ListAll returns all users (for debugging only - remove in production)
func (s *UserService) ListAll() []*models.User {
	s.mu.RLock()
	defer s.mu.RUnlock()

	users := make([]*models.User, 0, len(s.users))
	for _, user := range s.users {
		users = append(users, user)
	}
	return users
}

