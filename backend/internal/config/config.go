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
	DataDir         string
	MongoURI        string
	MongoDB         string
	MaxUploadSizeMB int64
}

func Load() *Config {
	// Cloud Run uses PORT env var
	port := getEnv("PORT", "8080")
	serverAddress := getEnv("SERVER_ADDRESS", ":"+port)

	return &Config{
		ServerAddress:   serverAddress,
		JWTSecret:       getEnv("JWT_SECRET", "your-secret-key-change-in-production"),
		JWTExpiration:   24 * time.Hour,
		UploadDir:       getEnv("UPLOAD_DIR", "./uploads"),
		DataDir:         getEnv("DATA_DIR", "./data"),
		MongoURI:        getEnv("MONGO_URI", ""),
		MongoDB:         getEnv("MONGO_DB", "rummage"),
		MaxUploadSizeMB: 10,
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
