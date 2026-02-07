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

	// Firebase Storage bucket for moderation (e.g. "rummage-31244.firebasestorage.app").
	FirebaseBucket string

	// Support form (public endpoint)
	SendGridAPIKey   string
	SupportToEmail   string
	SupportFromEmail string
	RecaptchaSecret  string
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

		FirebaseBucket: getEnv("FIREBASE_BUCKET", ""),

		SendGridAPIKey:   getEnv("SENDGRID_API_KEY", ""),
		SupportToEmail:   getEnv("SUPPORT_TO_EMAIL", "support@ludicrousapps.io"),
		SupportFromEmail: getEnv("SUPPORT_FROM_EMAIL", ""),
		RecaptchaSecret:  getEnv("RECAPTCHA_SECRET", ""),
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
