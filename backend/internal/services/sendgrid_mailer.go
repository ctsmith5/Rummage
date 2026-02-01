package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type SendGridMailer struct {
	APIKey     string
	FromEmail  string
	ToEmail    string
	HTTPClient *http.Client
	Endpoint   string
}

func NewSendGridMailer(apiKey string, fromEmail string, toEmail string) *SendGridMailer {
	to := strings.TrimSpace(toEmail)
	if to == "" {
		to = "support@ludicrousapps.io"
	}
	return &SendGridMailer{
		APIKey:    strings.TrimSpace(apiKey),
		FromEmail: strings.TrimSpace(fromEmail),
		ToEmail:   to,
		Endpoint:  "https://api.sendgrid.com/v3/mail/send",
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

type sendGridEmailAddress struct {
	Email string `json:"email"`
	Name  string `json:"name,omitempty"`
}

type sendGridContent struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type sendGridPersonalization struct {
	To         []sendGridEmailAddress `json:"to"`
	Subject    string                 `json:"subject"`
	CustomArgs map[string]string      `json:"custom_args,omitempty"`
}

type sendGridMailSendRequest struct {
	Personalizations []sendGridPersonalization `json:"personalizations"`
	From             sendGridEmailAddress      `json:"from"`
	ReplyTo          *sendGridEmailAddress     `json:"reply_to,omitempty"`
	Content          []sendGridContent         `json:"content"`
}

func (m *SendGridMailer) SendSupportEmail(ctx context.Context, ticket string, userName string, userEmail string, message string) error {
	if m == nil {
		return fmt.Errorf("sendgrid mailer not configured")
	}
	if m.APIKey == "" {
		return fmt.Errorf("missing SENDGRID_API_KEY")
	}
	if m.FromEmail == "" {
		return fmt.Errorf("missing SUPPORT_FROM_EMAIL")
	}
	if m.ToEmail == "" {
		return fmt.Errorf("missing SUPPORT_TO_EMAIL")
	}

	subject := fmt.Sprintf("Support Request: #%s", ticket)
	body := strings.TrimSpace(message)
	if body == "" {
		body = "(empty message)"
	}

	plain := fmt.Sprintf(
		"Support ticket: %s\nFrom: %s <%s>\n\nMessage:\n%s\n",
		ticket,
		strings.TrimSpace(userName),
		strings.TrimSpace(userEmail),
		body,
	)

	reqBody := sendGridMailSendRequest{
		Personalizations: []sendGridPersonalization{
			{
				To:      []sendGridEmailAddress{{Email: m.ToEmail}},
				Subject: subject,
				CustomArgs: map[string]string{
					"ticket": ticket,
				},
			},
		},
		From: sendGridEmailAddress{
			Email: m.FromEmail,
			Name:  "Rummage Support Form",
		},
		ReplyTo: &sendGridEmailAddress{
			Email: strings.TrimSpace(userEmail),
			Name:  strings.TrimSpace(userName),
		},
		Content: []sendGridContent{
			{Type: "text/plain", Value: plain},
		},
	}

	b, err := json.Marshal(reqBody)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.Endpoint, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+m.APIKey)
	req.Header.Set("Content-Type", "application/json")

	client := m.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// SendGrid returns 202 Accepted on success.
	if resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("sendgrid mail send http %d", resp.StatusCode)
	}
	return nil
}
