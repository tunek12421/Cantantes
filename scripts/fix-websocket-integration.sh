#!/bin/bash

# Script to complete Phase 3 WebSocket integration for Chat E2EE

echo "Fixing WebSocket integration..."

# Update main.go to include WebSocket routes
cat > src/cmd/server/main.go << 'ENDOFFILE'
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
	"chat-e2ee/internal/relay"

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

	// Initialize WebSocket relay service
	relayHandler, hub := relay.CreateRelayService(redis, jwtService)

	// Create Fiber app
	app := fiber.New(fiber.Config{
		AppName:      "Chat E2EE",
		ServerHeader: "Chat-E2EE",
		ErrorHandler: customErrorHandler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
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

		return c.JSON(fiber.Map{
			"status":  "healthy",
			"version": cfg.App.Version,
			"uptime":  time.Since(startTime).String(),
			"services": fiber.Map{
				"postgres": "connected",
				"redis":    "connected",
				"minio":    "connected",
				"websocket": fiber.Map{
					"hub_active": hub != nil,
					"stats": hub.GetStats(),
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
			"endpoints": fiber.Map{
				"auth": "/api/v1/auth/*",
				"websocket": "/ws",
				"stats": "/api/v1/ws/stats",
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

	// User routes
	userGroup := protected.Group("/users")
	userGroup.Get("/me", func(c *fiber.Ctx) error {
		userID := c.Locals("userID").(string)
		return c.JSON(fiber.Map{
			"user_id": userID,
			"message": "User profile endpoint - to be implemented",
		})
	})

	// WebSocket stats endpoint
	protected.Get("/ws/stats", relayHandler.GetStats())

	// WebSocket route with authentication check
	app.Use("/ws", relayHandler.UpgradeHandler())
	app.Get("/ws", websocket.New(relayHandler.WebSocketHandler()))

	// Log MinIO client usage (temporary)
	_ = minioClient

	// Start server with graceful shutdown
	go func() {
		addr := fmt.Sprintf(":%s", cfg.App.Port)
		log.Printf("Server starting on %s", addr)
		log.Printf("Environment: %s", cfg.App.Env)
		log.Printf("Debug mode: %v", cfg.App.Debug)
		log.Printf("WebSocket endpoint: ws://localhost%s/ws", addr)

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
ENDOFFILE

# Fix the WebSocket handler to properly implement fiber.Handler
echo "Fixing WebSocket handler implementation..."
cat > src/internal/relay/websocket_fix.go << 'ENDOFFILE'
package relay

import (
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
)

// WebSocketHandler returns the actual WebSocket handler function
func (h *Handler) WebSocketHandler() func(*websocket.Conn) {
	return func(c *websocket.Conn) {
		userID, ok := c.Locals("userID").(string)
		if !ok || userID == "" {
			c.Close()
			return
		}

		deviceID, ok := c.Locals("deviceID").(string)
		if !ok || deviceID == "" {
			c.Close()
			return
		}

		client := NewClient(h.hub, c, userID, deviceID)
		client.Start()
	}
}
ENDOFFILE

echo "✅ WebSocket integration fixed!"
echo ""
echo "Next steps:"
echo "1. Rebuild backend: cd docker && docker-compose build backend"
echo "2. Restart backend: docker-compose restart backend"
echo "3. Test WebSocket again: ./scripts/test-websocket.sh"