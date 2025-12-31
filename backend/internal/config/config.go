package config

import (
	"os"
	"time"
)

type Config struct {
	ServerAddress   string
	JWTSecret       string
	JWTExpiration   time.Duration
	UploadDir       string
	MaxUploadSizeMB int64
}

func Load() *Config {
	return &Config{
		ServerAddress:   getEnv("SERVER_ADDRESS", ":8080"),
		JWTSecret:       getEnv("JWT_SECRET", "your-secret-key-change-in-production"),
		JWTExpiration:   24 * time.Hour,
		UploadDir:       getEnv("UPLOAD_DIR", "./uploads"),
		MaxUploadSizeMB: 10,
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

