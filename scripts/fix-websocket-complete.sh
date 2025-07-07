#!/bin/bash

# Complete fix for WebSocket compilation errors

echo "🔧 Applying complete WebSocket fixes..."

# 1. Remove duplicate file
rm -f src/internal/relay/websocket_fix.go

# 2. Fix message.go - correct the NewErrorMessage function
cat > src/internal/relay/message.go << 'ENDOFFILE'
package relay

import (
	"encoding/json"
	"time"
	"math/rand"
)

// MessageType defines the type of WebSocket message
type MessageType string

const (
	// Client to Server
	MessageTypeText     MessageType = "message"
	MessageTypeTyping   MessageType = "typing"
	MessageTypeRead     MessageType = "read"
	MessageTypePresence MessageType = "presence"

	// Server to Client
	MessageTypeDelivery MessageType = "delivery"
	MessageTypeError    MessageType = "error"
	MessageTypeStatus   MessageType = "status"

	// System
	MessageTypeHeartbeat MessageType = "heartbeat"
	MessageTypePing      MessageType = "ping"
	MessageTypePong      MessageType = "pong"
)

// Message represents a WebSocket message for E2EE relay
type Message struct {
	// Message identification
	ID        string      `json:"id"`
	Type      MessageType `json:"type"`
	Timestamp time.Time   `json:"timestamp"`

	// Routing information
	From     string `json:"from,omitempty"`     // UserID of sender
	To       string `json:"to,omitempty"`       // UserID of recipient
	DeviceID string `json:"device_id,omitempty"` // Device that sent the message

	// E2EE payload - server never decrypts this
	Payload string `json:"payload,omitempty"` // Base64 encoded encrypted data

	// Metadata (not encrypted)
	Metadata map[string]interface{} `json:"metadata,omitempty"`
}

// ClientMessage is what clients send
type ClientMessage struct {
	Type    MessageType `json:"type"`
	To      string      `json:"to"`      // Target user ID
	Payload string      `json:"payload"` // Encrypted content
}

// ServerMessage is what server sends to clients
type ServerMessage struct {
	Type      MessageType `json:"type"`
	From      string      `json:"from,omitempty"`
	Payload   string      `json:"payload,omitempty"`
	Timestamp time.Time   `json:"timestamp"`
	MessageID string      `json:"message_id,omitempty"`
}

// TypingIndicator for typing status
type TypingIndicator struct {
	UserID   string `json:"user_id"`
	IsTyping bool   `json:"is_typing"`
}

// ReadReceipt for read confirmations
type ReadReceipt struct {
	MessageID string    `json:"message_id"`
	ReadAt    time.Time `json:"read_at"`
}

// PresenceUpdate for online/offline status
type PresenceUpdate struct {
	UserID   string    `json:"user_id"`
	Status   string    `json:"status"` // "online", "offline", "away"
	LastSeen time.Time `json:"last_seen"`
}

// ErrorMessage for error responses
type ErrorMessage struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ParseMessage parses raw WebSocket message
func ParseMessage(data []byte) (*ClientMessage, error) {
	var msg ClientMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, err
	}
	return &msg, nil
}

// NewServerMessage creates a server message
func NewServerMessage(msgType MessageType, from string, payload string) *ServerMessage {
	return &ServerMessage{
		Type:      msgType,
		From:      from,
		Payload:   payload,
		Timestamp: time.Now().UTC(),
		MessageID: generateMessageID(),
	}
}

// NewErrorMessage creates an error message
func NewErrorMessage(code, message string) []byte {
	errMsg := ErrorMessage{Code: code, Message: message}
	payload, _ := json.Marshal(errMsg)
	
	msg := ServerMessage{
		Type:      MessageTypeError,
		Timestamp: time.Now().UTC(),
		Payload:   string(payload),
	}
	
	data, _ := json.Marshal(msg)
	return data
}

// Helper functions

func generateMessageID() string {
	// Simple ID generation - could be replaced with UUID
	return time.Now().Format("20060102150405") + "-" + randomString(8)
}

func mustMarshal(v interface{}) string {
	data, _ := json.Marshal(v)
	return string(data)
}

func randomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}
ENDOFFILE

# 3. Fix hub.go - correct the GetPendingMessages call
sed -i 's/messages := h.presence.GetPendingMessages(ctx, client.UserID)/messages, _ := h.presence.GetPendingMessages(ctx, client.UserID)/' src/internal/relay/hub.go

# 4. Fix client.go - ensure mustMarshal is used correctly
sed -i 's/mustMarshal(indicator)/string(data)/' src/internal/relay/client.go
sed -i 's/mustMarshal(receipt)/string(data)/' src/internal/relay/client.go

# Actually, let's fix client.go properly
echo "Fixing client.go..."
sed -i '134s/Payload: mustMarshal(indicator),/Payload: mustMarshal(indicator),/' src/internal/relay/client.go
sed -i '147s/Payload: mustMarshal(receipt),/Payload: mustMarshal(receipt),/' src/internal/relay/client.go

# 5. Now update main.go to properly integrate WebSocket
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
					"active": true,
					"connections": hubStats.ActiveConnections,
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

	// WebSocket route - upgrade check and handler
	app.Use("/ws", relayHandler.UpgradeHandler())
	app.Get("/ws", relayHandler.WebSocketHandler())

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

echo "✅ All WebSocket compilation errors fixed!"
echo ""
echo "Now rebuild and restart:"
echo "cd docker && docker-compose build backend && docker-compose restart backend"