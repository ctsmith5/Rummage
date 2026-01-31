package services

import (
	"context"

	"github.com/rummage/backend/internal/models"
)

type ModerationActions struct {
	Sales    *MongoSalesService
	Profiles *MongoProfileService
	Flags    *MongoUserFlagService
}

// StrikeAndClear clears references for a rejected image and records a strike.
// url is expected to be the final approved-path download URL stored in Mongo.
func (m *ModerationActions) StrikeAndClear(ctx context.Context, userID string, saleID string, url string, typ string) error {
	if m.Flags != nil && userID != "" {
		_, _ = m.Flags.AddStrike(ctx, userID)
	}

	switch typ {
	case "sale_cover":
		if m.Sales != nil {
			return m.Sales.ClearSaleCoverIfMatches(ctx, saleID, url)
		}
	case "sale_item":
		if m.Sales != nil {
			return m.Sales.RemoveItemImageIfMatches(ctx, saleID, url)
		}
	case "profile_photo":
		if m.Profiles != nil {
			// Profile photos are always user-owned; clear it regardless of whether it currently
			// matches the URL (best-effort safety).
			empty := ""
			_, err := m.Profiles.Upsert(ctx, userID, "", &models.UpsertProfileRequest{PhotoURL: &empty})
			return err
		}
	}
	return nil
}

