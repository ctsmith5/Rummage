package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"

	"github.com/rummage/backend/internal/models"
)

type contextKey string

const UserIDKey contextKey = "userID"

// JWTAuth middleware validates JWT tokens
func JWTAuth(jwtSecret string) func(http.Handler) http.Handler {
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

			token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
				if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
					return nil, jwt.ErrSignatureInvalid
				}
				return []byte(jwtSecret), nil
			})

			if err != nil || !token.Valid {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid or expired token"))
				return
			}

			claims, ok := token.Claims.(jwt.MapClaims)
			if !ok {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid token claims"))
				return
			}

			userID, ok := claims["user_id"].(string)
			if !ok {
				writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Invalid user ID in token"))
				return
			}

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
	// Using a simple approach here; in production, use json.Encoder
	if resp, ok := data.(models.APIResponse); ok {
		jsonData := `{"success":` + boolToString(resp.Success)
		if resp.Error != "" {
			jsonData += `,"error":"` + resp.Error + `"`
		}
		jsonData += `}`
		w.Write([]byte(jsonData))
	}
}

func boolToString(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

