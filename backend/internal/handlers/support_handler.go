package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type SupportHandler struct {
	recaptcha *services.RecaptchaVerifier
	mailer    *services.SendGridMailer
}

func NewSupportHandler(recaptcha *services.RecaptchaVerifier, mailer *services.SendGridMailer) *SupportHandler {
	return &SupportHandler{recaptcha: recaptcha, mailer: mailer}
}

type supportRequestBody struct {
	Name           string `json:"name"`
	Email          string `json:"email"`
	Message        string `json:"message"`
	RecaptchaToken string `json:"recaptchaToken"`
}

func (h *SupportHandler) SubmitSupportRequest(w http.ResponseWriter, r *http.Request) {
	var req supportRequestBody
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	name := strings.TrimSpace(req.Name)
	email := strings.TrimSpace(req.Email)
	msg := strings.TrimSpace(req.Message)
	token := strings.TrimSpace(req.RecaptchaToken)

	errors := map[string]string{}
	if name == "" {
		errors["name"] = "Name is required"
	} else if len(name) > 120 {
		errors["name"] = "Name is too long"
	}

	if email == "" {
		errors["email"] = "Email is required"
	} else if len(email) > 254 {
		errors["email"] = "Email is too long"
	} else if _, err := mail.ParseAddress(email); err != nil {
		errors["email"] = "Email is invalid"
	}

	if msg == "" {
		errors["message"] = "Message is required"
	} else if len(msg) > 4000 {
		errors["message"] = "Message is too long"
	}

	if token == "" {
		errors["recaptchaToken"] = "reCAPTCHA token is required"
	}

	if len(errors) > 0 {
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	remoteIP := clientIP(r)

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	ok, reason, err := h.recaptcha.VerifyV2(ctx, token, remoteIP)
	if err != nil {
		log.Printf("[Support] recaptcha error ip=%s err=%v", remoteIP, err)
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to verify reCAPTCHA"))
		return
	}
	if !ok {
		log.Printf("[Support] recaptcha failed ip=%s reason=%s", remoteIP, reason)
		writeJSON(w, http.StatusForbidden, models.NewErrorResponse("reCAPTCHA verification failed"))
		return
	}

	ticket := generateSupportTicket()
	if err := h.mailer.SendSupportEmail(ctx, ticket, name, email, msg); err != nil {
		log.Printf("[Support] ticket=%s sendgrid error=%v", ticket, err)
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to send support request"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(map[string]string{
		"ticket": ticket,
	}))
}

func generateSupportTicket() string {
	// Example: RM-20260131-032508-A1B2C3D4
	now := time.Now().UTC().Format("20060102-150405")
	id := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))
	if len(id) > 8 {
		id = id[:8]
	}
	return "RM-" + now + "-" + id
}

func clientIP(r *http.Request) string {
	// Cloud Run typically provides X-Forwarded-For. Use first IP if present.
	xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For"))
	if xff != "" {
		parts := strings.Split(xff, ",")
		if len(parts) > 0 {
			ip := strings.TrimSpace(parts[0])
			if net.ParseIP(ip) != nil {
				return ip
			}
		}
	}

	// Fallback to RemoteAddr.
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err == nil && net.ParseIP(host) != nil {
		return host
	}
	if net.ParseIP(r.RemoteAddr) != nil {
		return r.RemoteAddr
	}
	return ""
}

