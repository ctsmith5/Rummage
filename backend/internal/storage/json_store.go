package storage

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// JSONStore provides thread-safe JSON file-based persistence
type JSONStore struct {
	mu       sync.RWMutex
	filePath string
}

// NewJSONStore creates a new JSON store at the specified path
func NewJSONStore(dataDir, filename string) (*JSONStore, error) {
	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, err
	}

	return &JSONStore{
		filePath: filepath.Join(dataDir, filename),
	}, nil
}

// Load reads data from the JSON file into the provided interface
func (s *JSONStore) Load(data interface{}) error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	file, err := os.Open(s.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// File doesn't exist yet, not an error
			return nil
		}
		return err
	}
	defer file.Close()

	return json.NewDecoder(file).Decode(data)
}

// Save writes data to the JSON file
func (s *JSONStore) Save(data interface{}) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Write to temp file first, then rename (atomic operation)
	tempFile := s.filePath + ".tmp"
	file, err := os.Create(tempFile)
	if err != nil {
		return err
	}

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(data); err != nil {
		file.Close()
		os.Remove(tempFile)
		return err
	}

	if err := file.Close(); err != nil {
		os.Remove(tempFile)
		return err
	}

	// Atomic rename
	return os.Rename(tempFile, s.filePath)
}

// Exists checks if the storage file exists
func (s *JSONStore) Exists() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()

	_, err := os.Stat(s.filePath)
	return err == nil
}


