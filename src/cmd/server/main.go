package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"chat-e2ee/internal/auth"
	"chat-e2ee/internal/config"
	"chat-e2ee/internal/database"
	"chat-e2ee/internal/discovery"
	"chat-e2ee/internal/gallery"
	"chat-e2ee/internal/media"
	"chat-e2ee/internal/relay"
	"chat-e2ee/internal/users"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/websocket/v2"
	"github.com/joho/godotenv"
)

func main() {
	// Load .env file in development
	if os.Getenv("APP_ENV") != "production" {
		if err := godotenv.Load(); err != nil {
			log.Println("No .env file found")
		}
	}

	// Load configuration
	cfg := config.Load()

	// Initialize database connections
	db, err := database.NewPostgresConnection(cfg.Database)
	if err != nil {
		log.Fatal("Failed to connect to PostgreSQL:", err)
	}
	defer db.Close()

	redis, err := database.NewRedisConnection(cfg.Redis)
	if err != nil {
		log.Fatal("Failed to connect to Redis:", err)
	}
	defer redis.Close()

	// Initialize MinIO connection
	minioClient, err := database.NewMinIOConnection(cfg.MinIO)
	if err != nil {
		log.Fatal("Failed to connect to MinIO:", err)
	}

	// Initialize services
	jwtService := auth.NewJWTService(
		cfg.JWT.Secret,
		cfg.JWT.AccessTokenDuration,
		cfg.JWT.RefreshTokenDuration,
	)

	// SMS Provider selection
	var smsProvider auth.SMSProvider
	if cfg.SMS.Provider == "twilio" && cfg.SMS.AccountSID != "" {
		smsProvider = auth.NewTwilioProvider(
			cfg.SMS.AccountSID,
			cfg.SMS.AuthToken,
			cfg.SMS.FromNumber,
		)
		log.Println("Using Twilio SMS provider")
	} else {
		smsProvider = &auth.MockSMSProvider{}
		log.Println("Using Mock SMS provider (development mode)")
	}

	// Initialize stores
	otpStore := auth.NewRedisOTPStore(redis)
	sessionStore := auth.NewSessionStore(redis)

	// Initialize SMS service
	smsService := auth.NewSMSService(smsProvider, otpStore)

	// Initialize handlers
	authHandler := auth.NewAuthHandler(db, jwtService, smsService, sessionStore)

	// Initialize media handler
	mediaHandler := media.NewHandler(db, minioClient, cfg.MinIO.BucketMedia, cfg.MinIO.BucketThumbs, cfg.MinIO.BucketTemp)

	// Initialize gallery handler
	galleryHandler := gallery.NewHandler(db)

	// Initialize user handler
	userHandler := users.NewHandler(db, minioClient, cfg.MinIO.BucketMedia)

	// Initialize discovery handler
	discoveryHandler := discovery.NewHandler(db)

	// Initialize WebSocket relay service - CRITICAL!
	log.Println("Initializing WebSocket relay service...")
	relayHandler, hub := relay.CreateRelayService(redis, jwtService)
	if relayHandler == nil || hub == nil {
		log.Fatal("Failed to initialize WebSocket relay service")
	}
	log.Printf("WebSocket relay service initialized: handler=%v, hub=%v", relayHandler != nil, hub != nil)

	// Create Fiber app
	app := fiber.New(fiber.Config{
		AppName:      "Chat E2EE",
		ServerHeader: "Chat-E2EE",
		ErrorHandler: customErrorHandler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
		BodyLimit:    100 * 1024 * 1024, // 100MB for file uploads
	})

	// Middleware
	app.Use(recover.New())
	app.Use(logger.New(logger.Config{
		Format: "[${time}] ${status} - ${latency} ${method} ${path}\n",
	}))
	app.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.App.CORSOrigins,
		AllowMethods:     "GET,POST,PUT,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Accept,Authorization",
		AllowCredentials: true,
		MaxAge:           3600,
	}))

	// Health check endpoint
	app.Get("/health", func(c *fiber.Ctx) error {
		// Check database connections
		if err := db.Ping(); err != nil {
			return c.Status(503).JSON(fiber.Map{
				"status": "unhealthy",
				"error":  "Database connection failed",
			})
		}

		if err := redis.Ping(context.Background()).Err(); err != nil {
			return c.Status(503).JSON(fiber.Map{
				"status": "unhealthy",
				"error":  "Redis connection failed",
			})
		}

		hubStats := hub.GetStats()

		return c.JSON(fiber.Map{
			"status":  "healthy",
			"version": cfg.App.Version,
			"uptime":  time.Since(startTime).String(),
			"services": fiber.Map{
				"postgres": "connected",
				"redis":    "connected",
				"minio":    "connected",
				"websocket": fiber.Map{
					"hub_active": true,
					"stats":      hubStats,
				},
			},
		})
	})

	// API routes
	api := app.Group("/api/v1")

	// Public routes
	api.Get("/", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"message": "Chat E2EE API v1",
			"docs":    "/api/v1/docs",
			"status":  "operational",
			"phase":   "5 - Routes Complete",
			"endpoints": fiber.Map{
				"auth":      "/api/v1/auth/*",
				"websocket": "/ws",
				"stats":     "/api/v1/ws/stats",
				"media":     "/api/v1/media/*",
				"gallery":   "/api/v1/gallery/*",
				"users":     "/api/v1/users/*",
				"models":    "/api/v1/models/*",
				"discovery": "/api/v1/models/*",
			},
		})
	})

	// Auth routes (public)
	authGroup := api.Group("/auth")
	authGroup.Post("/request-otp", auth.RateLimitMiddleware(3), authHandler.RequestOTP)
	authGroup.Post("/verify-otp", auth.RateLimitMiddleware(5), authHandler.VerifyOTP)
	authGroup.Post("/refresh", authHandler.RefreshToken)

	// Protected routes
	protected := api.Group("/", auth.AuthMiddleware(jwtService))
	protected.Post("/auth/logout", authHandler.Logout)

	// User routes (protected)
	userGroup := protected.Group("/users")
	userGroup.Get("/me", userHandler.GetMe)
	userGroup.Put("/me", userHandler.UpdateMe)
	userGroup.Post("/avatar", userHandler.UpdateAvatar)
	userGroup.Get("/contacts", userHandler.GetContacts)
	userGroup.Post("/contacts", userHandler.AddContact)
	userGroup.Put("/contacts/:id", userHandler.UpdateContact)
	userGroup.Delete("/contacts/:id", userHandler.RemoveContact)
	userGroup.Post("/contacts/:id/block", userHandler.BlockContact)
	userGroup.Post("/contacts/:id/unblock", userHandler.UnblockContact)

	// Public user routes
	publicUsers := api.Group("/users")
	publicUsers.Get("/:id", userHandler.GetUser)

	// Media routes (protected)
	mediaGroup := protected.Group("/media")
	mediaGroup.Post("/upload", mediaHandler.Upload)
	mediaGroup.Get("/:id", mediaHandler.GetFile)
	mediaGroup.Delete("/:id", mediaHandler.DeleteFile)
	mediaGroup.Get("/thumbnail/:name", func(c *fiber.Ctx) error {
		// Handle thumbnail retrieval
		thumbName := c.Params("name")
		thumbService := media.NewThumbnailService(minioClient, cfg.MinIO.BucketThumbs, cfg.MinIO.BucketMedia)

		reader, contentType, err := thumbService.GetThumbnail(c.Context(), thumbName)
		if err != nil {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Thumbnail not found",
			})
		}
		defer reader.Close()

		c.Set("Content-Type", contentType)
		return c.SendStream(reader)
	})
	mediaGroup.Get("/:id/url", mediaHandler.GetPresignedURL)

	// Gallery routes (protected)
	galleryGroup := protected.Group("/gallery")
	galleryGroup.Get("/", galleryHandler.GetMyGallery)
	galleryGroup.Post("/media", mediaHandler.AddToGallery)
	galleryGroup.Delete("/media/:id", mediaHandler.RemoveFromGallery)
	galleryGroup.Put("/settings", galleryHandler.UpdateGallerySettings)
	galleryGroup.Get("/stats", galleryHandler.GetGalleryStats)

	// Public gallery routes (with optional auth)
	publicGallery := api.Group("/gallery", auth.OptionalAuthMiddleware(jwtService))
	publicGallery.Get("/discover", galleryHandler.DiscoverGalleries)
	publicGallery.Get("/:userId", galleryHandler.GetUserGallery)

	// Models discovery routes (public with optional auth)
	modelsGroup := api.Group("/models", auth.OptionalAuthMiddleware(jwtService))
	modelsGroup.Get("/", discoveryHandler.GetModels)
	modelsGroup.Get("/search", discoveryHandler.SearchModels)
	modelsGroup.Get("/popular", discoveryHandler.GetPopularModels)
	modelsGroup.Get("/new", discoveryHandler.GetNewModels)
	modelsGroup.Get("/online", discoveryHandler.GetOnlineModels)
	modelsGroup.Get("/:id", discoveryHandler.GetModelProfile)

	// ===== WEBSOCKET ROUTES - PHASE 3 CRITICAL SECTION =====
	log.Println("Registering WebSocket routes...")

	// WebSocket stats endpoint (protected)
	protected.Get("/ws/stats", relayHandler.GetStats())

	// Test WebSocket endpoint (sin autenticación)
	app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {
		log.Println("[TEST-WS] New connection")
		c.WriteMessage(websocket.TextMessage, []byte("Welcome to test WebSocket!"))
		for {
			mt, msg, err := c.ReadMessage()
			if err != nil {
				log.Printf("[TEST-WS] Error: %v", err)
				break
			}
			log.Printf("[TEST-WS] Received: %s", string(msg))
			c.WriteMessage(mt, append([]byte("Echo: "), msg...))
		}
	}))
	log.Println("✅ Registered /test-ws endpoint")
	log.Println("✅ Registered /api/v1/ws/stats")

	// WebSocket route - MUST BE BEFORE app.Listen()!
	app.Use("/ws", relayHandler.UpgradeHandler())
	app.Get("/ws", relayHandler.WebSocketHandler())
	log.Println("✅ Registered /ws WebSocket endpoint")

	// Debug endpoint to verify routes work
	app.Get("/debug/phase5", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"message": "Phase 5 API Routes completed!",
			"endpoints": fiber.Map{
				"auth": fiber.Map{
					"request-otp": "POST /api/v1/auth/request-otp",
					"verify-otp":  "POST /api/v1/auth/verify-otp",
					"refresh":     "POST /api/v1/auth/refresh",
					"logout":      "POST /api/v1/auth/logout",
				},
				"users": fiber.Map{
					"profile":        "GET /api/v1/users/me",
					"update":         "PUT /api/v1/users/me",
					"avatar":         "POST /api/v1/users/avatar",
					"contacts":       "GET /api/v1/users/contacts",
					"add-contact":    "POST /api/v1/users/contacts",
					"update-contact": "PUT /api/v1/users/contacts/:id",
					"remove-contact": "DELETE /api/v1/users/contacts/:id",
					"block":          "POST /api/v1/users/contacts/:id/block",
					"unblock":        "POST /api/v1/users/contacts/:id/unblock",
					"public-profile": "GET /api/v1/users/:id",
				},
				"models": fiber.Map{
					"list":    "GET /api/v1/models",
					"search":  "GET /api/v1/models/search",
					"popular": "GET /api/v1/models/popular",
					"new":     "GET /api/v1/models/new",
					"online":  "GET /api/v1/models/online",
					"profile": "GET /api/v1/models/:id",
				},
				"media": fiber.Map{
					"upload":    "POST /api/v1/media/upload",
					"get":       "GET /api/v1/media/:id",
					"delete":    "DELETE /api/v1/media/:id",
					"thumbnail": "GET /api/v1/media/thumbnail/:name",
				},
				"gallery": fiber.Map{
					"my-gallery":   "GET /api/v1/gallery",
					"add-media":    "POST /api/v1/gallery/media",
					"remove-media": "DELETE /api/v1/gallery/media/:id",
					"settings":     "PUT /api/v1/gallery/settings",
					"stats":        "GET /api/v1/gallery/stats",
					"discover":     "GET /api/v1/gallery/discover",
					"user-gallery": "GET /api/v1/gallery/:userId",
				},
				"websocket": fiber.Map{
					"connect": "WS /ws?token=JWT_TOKEN",
					"stats":   "GET /api/v1/ws/stats",
				},
			},
		})
	})
	log.Println("✅ Registered /debug/phase5")
	// ===== END WEBSOCKET ROUTES =====

	// Log all registered routes (debug)
	routes := app.GetRoutes()
	log.Printf("Total routes registered: %d", len(routes))
	for _, route := range routes {
		if route.Path == "/ws" || route.Path == "/api/v1/ws/stats" ||
			route.Path == "/debug/phase5" || route.Path == "/api/v1/media/upload" ||
			route.Path == "/api/v1/gallery" || route.Path == "/api/v1/users/me" ||
			route.Path == "/api/v1/models" {
			log.Printf("  ✅ %s %s", route.Method, route.Path)
		}
	}

	// Start server with graceful shutdown
	go func() {
		addr := fmt.Sprintf(":%s", cfg.App.Port)
		log.Printf("=== PHASE 5 COMPLETE ===")
		log.Printf("Server starting on %s", addr)
		log.Printf("Environment: %s", cfg.App.Env)
		log.Printf("Debug mode: %v", cfg.App.Debug)
		log.Printf("All API routes implemented!")
		log.Printf("========================")
		log.Printf("WebSocket endpoint: ws://localhost%s/ws", addr)
		log.Printf("WebSocket stats: http://localhost%s/api/v1/ws/stats", addr)
		log.Printf("Media upload: http://localhost%s/api/v1/media/upload", addr)
		log.Printf("Gallery: http://localhost%s/api/v1/gallery", addr)
		log.Printf("User profile: http://localhost%s/api/v1/users/me", addr)
		log.Printf("Model discovery: http://localhost%s/api/v1/models", addr)
		log.Printf("========================")

		if err := app.Listen(addr); err != nil {
			log.Fatal("Server failed to start:", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt)
	<-quit

	log.Println("Shutting down server...")
	if err := app.Shutdown(); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}
	log.Println("Server stopped")
}

var startTime = time.Now()

func customErrorHandler(c *fiber.Ctx, err error) error {
	code := fiber.StatusInternalServerError
	message := "Internal Server Error"

	if e, ok := err.(*fiber.Error); ok {
		code = e.Code
		message = e.Message
	}

	// Log errors in development
	if os.Getenv("APP_ENV") != "production" {
		log.Printf("Error: %v", err)
	}

	return c.Status(code).JSON(fiber.Map{
		"error": message,
		"code":  code,
	})
}
