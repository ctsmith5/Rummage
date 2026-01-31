package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

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

	// Mongo is required. Fail fast if not configured or not reachable.
	if cfg.MongoURI == "" {
		log.Fatalf("MONGO_URI is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	salesService, err := services.NewMongoSalesService(ctx, cfg.MongoURI, cfg.MongoDB)
	if err != nil {
		// Common cause: Atlas Network Access doesn't allow Cloud Run egress.
		log.Fatalf("Failed to initialize MongoDB sales service: %v", err)
	}
	favoriteService, err := services.NewMongoFavoriteService(ctx, cfg.MongoURI, cfg.MongoDB, salesService)
	if err != nil {
		log.Fatalf("Failed to initialize MongoDB favorites service: %v", err)
	}
	profileService, err := services.NewMongoProfileService(ctx, cfg.MongoURI, cfg.MongoDB)
	if err != nil {
		log.Fatalf("Failed to initialize MongoDB profile service: %v", err)
	}
	accountService, err := services.NewMongoAccountService(ctx, cfg.MongoURI, cfg.MongoDB)
	if err != nil {
		log.Fatalf("Failed to initialize MongoDB account service: %v", err)
	}
	imageService := services.NewImageService(cfg.UploadDir)

	// Initialize handlers
	salesHandler := handlers.NewSalesHandler(salesService)
	favoriteHandler := handlers.NewFavoriteHandler(favoriteService)
	imageHandler := handlers.NewImageHandler(imageService, cfg.MaxUploadSizeMB)
	profileHandler := handlers.NewProfileHandler(profileService, authClient)
	accountHandler := handlers.NewAccountHandler(accountService)

	// Create router
	r := chi.NewRouter()

	// Global middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RequestID)
	r.Use(cors.Handler(cors.Options{
		// Browser note: you cannot use `Access-Control-Allow-Origin: *` together with
		// `Access-Control-Allow-Credentials: true`. Since we auth via Bearer tokens
		// (no cookies), keep credentials disabled so the API is callable from the web.
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "Origin", "X-Requested-With", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: false,
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
				r.Get("/mine", salesHandler.ListMySales)
				r.Get("/search", salesHandler.SearchSales)
				r.Get("/bounds", salesHandler.ListSalesByBounds)
				r.Post("/", salesHandler.CreateSale)

				r.Route("/{saleId}", func(r chi.Router) {
					r.Get("/", salesHandler.GetSale)
					r.Put("/", salesHandler.UpdateSale)
					r.Put("/cover", salesHandler.SetSaleCoverPhoto)
					r.Delete("/", salesHandler.DeleteSale)
					r.Post("/start", salesHandler.StartSale)
					r.Post("/end", salesHandler.EndSale)

					// Items
					r.Post("/items", salesHandler.AddItem)
					r.Put("/items/{itemId}", salesHandler.UpdateItem)
					r.Delete("/items/{itemId}", salesHandler.DeleteItem)

					// Favorites
					r.Post("/favorite", favoriteHandler.AddFavorite)
					r.Delete("/favorite", favoriteHandler.RemoveFavorite)
				})
			})

			// Favorites list
			r.Get("/favorites", favoriteHandler.ListFavorites)
			r.Get("/favorites/sales", favoriteHandler.ListFavoriteSales)

			// Profile / account
			r.Route("/profile", func(r chi.Router) {
				r.Get("/", profileHandler.GetProfile)
				r.Get("/{userId}", profileHandler.GetPublicProfileByUserID)
				r.Put("/", profileHandler.UpsertProfile)
			})
			r.Route("/account", func(r chi.Router) {
				r.Delete("/", accountHandler.DeleteAccount)
			})

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
