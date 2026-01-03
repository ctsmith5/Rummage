package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/models"
	"github.com/rummage/backend/internal/services"
)

type SalesHandler struct {
	salesService *services.SalesService
}

func NewSalesHandler(salesService *services.SalesService) *SalesHandler {
	return &SalesHandler{
		salesService: salesService,
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

	// Read and log the raw body for debugging
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("[CreateSale] Error reading body: %v", err)
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse("Failed to read request body"))
		return
	}
	log.Printf("[CreateSale] Raw body: %s", string(bodyBytes))

	var req models.CreateSaleRequest
	if err := json.Unmarshal(bodyBytes, &req); err != nil {
		log.Printf("[CreateSale] JSON decode error: %v", err)
		writeJSON(w, http.StatusBadRequest, models.NewErrorResponse(fmt.Sprintf("Invalid request body: %v", err)))
		return
	}
	log.Printf("[CreateSale] Parsed request: %+v", req)

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

	sales, err := h.salesService.ListByBounds(minLat, maxLat, minLng, maxLng)
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

