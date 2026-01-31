package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func contextWithTimeout(parent context.Context, d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, d)
}

// isAtLeastAge returns true if dob implies age >= years as of now (UTC).
func isAtLeastAge(dob time.Time, years int) bool {
	now := time.Now().UTC()
	d := dob.UTC()
	cutoff := time.Date(now.Year()-years, now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	// If born on/after cutoff date, they are younger than required age.
	return d.Before(cutoff) || d.Equal(cutoff)
}
