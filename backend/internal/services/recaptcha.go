package services

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type RecaptchaVerifier struct {
	Secret     string
	HTTPClient *http.Client
	Endpoint   string
}

type recaptchaVerifyResponse struct {
	Success    bool      `json:"success"`
	ChallengeT time.Time `json:"challenge_ts"`
	Hostname   string    `json:"hostname"`
	ErrorCodes []string  `json:"error-codes"`
}

func NewRecaptchaVerifier(secret string) *RecaptchaVerifier {
	return &RecaptchaVerifier{
		Secret:   secret,
		Endpoint: "https://www.google.com/recaptcha/api/siteverify",
		HTTPClient: &http.Client{
			Timeout: 8 * time.Second,
		},
	}
}

// VerifyV2 verifies a reCAPTCHA v2 checkbox token. Returns (ok, reason, error).
func (v *RecaptchaVerifier) VerifyV2(ctx context.Context, token string, remoteIP string) (bool, string, error) {
	if v == nil {
		return false, "verifier_not_configured", nil
	}
	if strings.TrimSpace(v.Secret) == "" {
		return false, "missing_secret", nil
	}
	tok := strings.TrimSpace(token)
	if tok == "" {
		return false, "missing_token", nil
	}

	form := url.Values{}
	form.Set("secret", v.Secret)
	form.Set("response", tok)
	if strings.TrimSpace(remoteIP) != "" {
		form.Set("remoteip", strings.TrimSpace(remoteIP))
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, v.Endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return false, "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	client := v.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}

	resp, err := client.Do(req)
	if err != nil {
		return false, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false, "", fmt.Errorf("recaptcha verify http %d", resp.StatusCode)
	}

	var out recaptchaVerifyResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false, "", err
	}
	if out.Success {
		return true, "", nil
	}
	if len(out.ErrorCodes) > 0 {
		return false, strings.Join(out.ErrorCodes, ","), nil
	}
	return false, "verification_failed", nil
}

