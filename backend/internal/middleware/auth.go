package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"
	fbauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"

	"github.com/rummage/backend/internal/models"
)

type contextKey string

const UserIDKey contextKey = "userID"

type FirebaseAuthConfig struct {
	// Optional. If provided, used to validate Firebase ID token audience/issuer.
	// This should match your Firebase project id (e.g. "rummage-31244").
	ProjectID string

	// Optional. If provided, used to create the Firebase App.
	// Otherwise Application Default Credentials will be used (recommended on Cloud Run).
	CredentialsJSON string
}

func NewFirebaseAuthClient(ctx context.Context, cfg FirebaseAuthConfig) (*fbauth.Client, error) {
	var appCfg *firebase.Config
	if cfg.ProjectID != "" {
		appCfg = &firebase.Config{ProjectID: cfg.ProjectID}
	}

	var app *firebase.App
	var err error

	if cfg.CredentialsJSON != "" {
		app, err = firebase.NewApp(ctx, appCfg, option.WithCredentialsJSON([]byte(cfg.CredentialsJSON)))
	} else {
		// Uses Application Default Credentials if available.
		app, err = firebase.NewApp(ctx, appCfg)
	}
	if err != nil {
		return nil, err
	}

	return app.Auth(ctx)
}

// FirebaseAuth middleware validates Firebase ID tokens and sets userID to Firebase UID.
func FirebaseAuth(authClient *fbauth.Client) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Authorization header required"))
				return
			}

			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || parts[0] != "Bearer" {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid authorization header format"))
				return
			}

			tokenString := parts[1]
			if authClient == nil {
				writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Auth not configured"))
				return
			}

			token, err := authClient.VerifyIDToken(r.Context(), tokenString)
			if err != nil {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid or expired token"))
				return
			}

			userID := token.UID

			ctx := context.WithValue(r.Context(), UserIDKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetUserID extracts user ID from context
func GetUserID(ctx context.Context) string {
	userID, ok := ctx.Value(UserIDKey).(string)
	if !ok {
		return ""
	}
	return userID
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

