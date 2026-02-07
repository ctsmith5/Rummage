package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type SalesHandler struct {
	salesService      services.SalesService
	moderationService *services.ModerationService
}

func NewSalesHandler(salesService services.SalesService, moderationService *services.ModerationService) *SalesHandler {
	return &SalesHandler{
		salesService:      salesService,
		moderationService: moderationService,
	}
}

func (h *SalesHandler) CreateSale(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		log.Println("[CreateSale] Unauthorized - no user ID in context")
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}
	log.Printf("[CreateSale] User: %s", userID)

	var req models.CreateSaleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	if errors := req.Validate(); len(errors) > 0 {
		log.Printf("[CreateSale] Validation errors: %v", errors)
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	sale, err := h.salesService.Create(userID, &req)
	if err != nil {
		log.Printf("[CreateSale] Service error: %v", err)
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to create sale"))
		return
	}

	log.Printf("[CreateSale] Sale created: %s", sale.ID)
	writeJSON(w, http.StatusCreated, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) GetSale(w http.ResponseWriter, r *http.Request) {
	saleID := chi.URLParam(r, "saleId")

	sale, err := h.salesService.GetByID(saleID)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to get sale"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) UpdateSale(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	var req models.UpdateSaleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	sale, err := h.salesService.Update(userID, saleID, &req)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to update this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to update sale"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) SetSaleCoverPhoto(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	var req models.SetSaleCoverPhotoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	coverURL := req.SaleCoverPhoto
	if h.moderationService != nil && strings.HasPrefix(coverURL, "pending/") {
		res, err := h.moderationService.ModerateAndPromote(r.Context(), coverURL, userID)
		if err != nil {
			if err == services.ErrImageRejected {
				writeJSON(w, http.StatusUnprocessableEntity, models.NewErrorResponse("Photo rejected — violates community guidelines"))
				return
			}
			log.Printf("[SetSaleCoverPhoto] moderation error: %v", err)
			writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to process image"))
			return
		}
		coverURL = res.ApprovedURL
	}

	sale, err := h.salesService.SetSaleCoverPhoto(userID, saleID, coverURL)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to update this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to update sale cover photo"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) DeleteSale(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	err := h.salesService.Delete(userID, saleID)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to delete this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to delete sale"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(map[string]string{"message": "Sale deleted successfully"}))
}

func (h *SalesHandler) StartSale(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	sale, err := h.salesService.StartSale(userID, saleID)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to start this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to start sale"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) EndSale(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	sale, err := h.salesService.EndSale(userID, saleID)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to end this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to end sale"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sale))
}

func (h *SalesHandler) ListMySales(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, models.NewErrorResponse("Unauthorized"))
		return
	}

	// Cap to a reasonable default.
	sales, err := h.salesService.ListByUser(userID, 500)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to list sales"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sales))
}

func (h *SalesHandler) ListSales(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()

	lat, _ := strconv.ParseFloat(query.Get("lat"), 64)
	lng, _ := strconv.ParseFloat(query.Get("lng"), 64)
	radius, _ := strconv.ParseFloat(query.Get("radius"), 64)

	if radius == 0 {
		radius = 10 // Default 10 miles
	}

	sales, err := h.salesService.ListNearby(lat, lng, radius)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to list sales"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sales))
}

func (h *SalesHandler) SearchSales(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()

	latStr := query.Get("lat")
	lngStr := query.Get("lng")
	q := strings.TrimSpace(query.Get("q"))

	if latStr == "" || lngStr == "" {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Missing required parameters: lat, lng"))
		return
	}
	if q == "" {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Missing required parameter: q"))
		return
	}

	lat, err1 := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err1 != nil || err2 != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid lat/lng"))
		return
	}

	radius, _ := strconv.ParseFloat(query.Get("radius"), 64)
	if radius == 0 {
		radius = 10 // Default 10 miles
	}

	sales, err := h.salesService.SearchNearby(lat, lng, radius, q)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to search sales"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sales))
}

func (h *SalesHandler) ListSalesByBounds(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()

	minLat, err1 := strconv.ParseFloat(query.Get("minLat"), 64)
	maxLat, err2 := strconv.ParseFloat(query.Get("maxLat"), 64)
	minLng, err3 := strconv.ParseFloat(query.Get("minLng"), 64)
	maxLng, err4 := strconv.ParseFloat(query.Get("maxLng"), 64)

	if err1 != nil || err2 != nil || err3 != nil || err4 != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Missing or invalid bounding box parameters (minLat, maxLat, minLng, maxLng)"))
		return
	}

	// Cap results to keep payloads and UI reasonable.
	limit := 500
	if rawLimit := query.Get("limit"); rawLimit != "" {
		if v, err := strconv.Atoi(rawLimit); err == nil && v > 0 {
			limit = v
		}
	}
	if limit > 500 {
		limit = 500
	}

	sales, err := h.salesService.ListByBounds(minLat, maxLat, minLng, maxLng, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to list sales"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(sales))
}

func (h *SalesHandler) AddItem(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")

	var req models.CreateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	if errors := req.Validate(); len(errors) > 0 {
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	if h.moderationService != nil && len(req.ImageURLs) > 0 {
		approved, err := h.moderationService.ModerateMultiple(r.Context(), req.ImageURLs, userID)
		if err != nil {
			if err == services.ErrImageRejected {
				writeJSON(w, http.StatusUnprocessableEntity, models.NewErrorResponse("Photo rejected — violates community guidelines"))
				return
			}
			log.Printf("[AddItem] moderation error: %v", err)
			writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to process image"))
			return
		}
		req.ImageURLs = approved
	}

	item, err := h.salesService.AddItem(userID, saleID, &req)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to add items to this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to add item"))
		return
	}

	writeJSON(w, http.StatusCreated, models.NewSuccessResponse(item))
}

func (h *SalesHandler) UpdateItem(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")
	itemID := chi.URLParam(r, "itemId")

	var req models.UpdateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Invalid request body"))
		return
	}

	if errors := req.Validate(); len(errors) > 0 {
		writeJSON(w, http.StatusBadRequest, models.NewValidationErrorResponse(errors))
		return
	}

	if h.moderationService != nil && len(req.ImageURLs) > 0 {
		approved, err := h.moderationService.ModerateMultiple(r.Context(), req.ImageURLs, userID)
		if err != nil {
			if err == services.ErrImageRejected {
				writeJSON(w, http.StatusUnprocessableEntity, models.NewErrorResponse("Photo rejected — violates community guidelines"))
				return
			}
			log.Printf("[UpdateItem] moderation error: %v", err)
			writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to process image"))
			return
		}
		req.ImageURLs = approved
	}

	item, err := h.salesService.UpdateItem(userID, saleID, itemID, &req)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrItemNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Item not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to update items for this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to update item"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(item))
}

func (h *SalesHandler) DeleteItem(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	saleID := chi.URLParam(r, "saleId")
	itemID := chi.URLParam(r, "itemId")

	err := h.salesService.DeleteItem(userID, saleID, itemID)
	if err != nil {
		if err == services.ErrSaleNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Sale not found"))
			return
		}
		if err == services.ErrItemNotFound {
			writeJSON(w, http.StatusNotFound, models.NewErrorResponse("Item not found"))
			return
		}
		if err == services.ErrUnauthorized {
			writeJSON(w, http.StatusForbidden, models.NewErrorResponse("Not authorized to delete items from this sale"))
			return
		}
		writeJSON(w, http.StatusInternalServerError, models.NewErrorResponse("Failed to delete item"))
		return
	}

	writeJSON(w, http.StatusOK, models.NewSuccessResponse(map[string]string{"message": "Item deleted successfully"}))
}
