package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/rummage/backend/internal/config"
	"github.com/rummage/backend/internal/handlers"
	appMiddleware "github.com/rummage/backend/internal/middleware"
	"github.com/rummage/backend/internal/services"
)

func main() {
	cfg := config.Load()

	// Firebase Auth (server-side verification of ID tokens)
	authClient, err := appMiddleware.NewFirebaseAuthClient(
		context.Background(),
		appMiddleware.FirebaseAuthConfig{
			ProjectID:       os.Getenv("FIREBASE_PROJECT_ID"),
			CredentialsJSON: os.Getenv("FIREBASE_CREDENTIALS_JSON"),
		},
	)
	if err != nil {
		log.Printf("Warning: failed to initialize Firebase Auth client: %v", err)
	}

	// Initialize services with persistent storage
	salesService := services.NewSalesService(cfg.DataDir)
	favoriteService := services.NewFavoriteService(cfg.DataDir)
	imageService := services.NewImageService(cfg.UploadDir)

	// Initialize handlers
	salesHandler := handlers.NewSalesHandler(salesService)
	favoriteHandler := handlers.NewFavoriteHandler(favoriteService)
	imageHandler := handlers.NewImageHandler(imageService, cfg.MaxUploadSizeMB)

	// Create router
	r := chi.NewRouter()

	// Global middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RequestID)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// API routes
	r.Route("/api", func(r chi.Router) {
		// Protected routes
		r.Group(func(r chi.Router) {
			r.Use(appMiddleware.FirebaseAuth(authClient))

			// Sales routes
			r.Route("/sales", func(r chi.Router) {
				r.Get("/", salesHandler.ListSales)
				r.Get("/bounds", salesHandler.ListSalesByBounds)
				r.Post("/", salesHandler.CreateSale)

				r.Route("/{saleId}", func(r chi.Router) {
					r.Get("/", salesHandler.GetSale)
					r.Put("/", salesHandler.UpdateSale)
					r.Delete("/", salesHandler.DeleteSale)
					r.Post("/start", salesHandler.StartSale)
					r.Post("/end", salesHandler.EndSale)

					// Items
					r.Post("/items", salesHandler.AddItem)
					r.Delete("/items/{itemId}", salesHandler.DeleteItem)

					// Favorites
					r.Post("/favorite", favoriteHandler.AddFavorite)
					r.Delete("/favorite", favoriteHandler.RemoveFavorite)
				})
			})

			// Favorites list
			r.Get("/favorites", favoriteHandler.ListFavorites)

			// Image upload
			r.Post("/upload", imageHandler.Upload)
			r.Delete("/upload/{imageId}", imageHandler.Delete)
		})
	})

	// Serve uploaded files
	workDir, _ := os.Getwd()
	filesDir := http.Dir(workDir + "/" + cfg.UploadDir)
	r.Handle("/uploads/*", http.StripPrefix("/uploads/", http.FileServer(filesDir)))

	log.Printf("🚀 Rummage API server starting on %s", cfg.ServerAddress)
	if err := http.ListenAndServe(cfg.ServerAddress, r); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

