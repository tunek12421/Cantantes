#!/bin/bash

# Fix backend issues for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Fixing Backend Issues ===${NC}\n"

# Navigate to project root
cd "$(dirname "$0")/.."

# 1. Fix main.go
echo -e "${YELLOW}1. Fixing main.go (unused variable)...${NC}"
cat > src/cmd/server/main.go << 'EOF'
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"chat-e2ee/internal/config"
	"chat-e2ee/internal/database"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
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
	
	// Log MinIO connection success (using the client to avoid "declared and not used" error)
	log.Printf("MinIO connected successfully to %s", cfg.MinIO.Endpoint)
	_ = minioClient // Will be used when we implement media upload endpoints

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
		})
	})

	// API routes will be added here
	api := app.Group("/api/v1")

	// Placeholder routes
	api.Get("/", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"message": "Chat E2EE API v1",
			"docs":    "/api/v1/docs",
		})
	})

	// Start server with graceful shutdown
	go func() {
		addr := fmt.Sprintf(":%s", cfg.App.Port)
		log.Printf("Server starting on %s", addr)
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

	return c.Status(code).JSON(fiber.Map{
		"error": message,
		"code":  code,
	})
}
EOF

echo -e "${GREEN}✓ main.go fixed${NC}"

# 2. Fix Dockerfile
echo -e "\n${YELLOW}2. Fixing Dockerfile (Go version)...${NC}"
cat > docker/backend/Dockerfile << 'EOF'
# Build stage
FROM golang:1.23-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make

# Set working directory
WORKDIR /app

# Copy go mod files (go.sum might not exist yet)
COPY src/go.mod ./
COPY src/go.sum* ./

# Download dependencies (this will create go.sum if it doesn't exist)
RUN go mod download

# Copy source code
COPY src/ .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.Version=$(date +%Y%m%d)" \
    -o chat-e2ee \
    cmd/server/main.go

# Final stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user
RUN addgroup -g 1000 -S chat && \
    adduser -u 1000 -S chat -G chat

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/chat-e2ee .

# Create directories for logs
RUN mkdir -p /app/logs && chown -R chat:chat /app

# Switch to non-root user
USER chat

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
CMD ["./chat-e2ee"]
EOF

echo -e "${GREEN}✓ Dockerfile fixed${NC}"

# 3. Test build locally
echo -e "\n${YELLOW}3. Testing build locally...${NC}"
cd src
if go build -o /tmp/test-build ./cmd/server; then
    echo -e "${GREEN}✓ Local build successful${NC}"
    rm /tmp/test-build
else
    echo -e "${RED}✗ Local build failed${NC}"
    exit 1
fi
cd ..

# 4. Clean up Docker
echo -e "\n${YELLOW}4. Cleaning up Docker...${NC}"
cd docker
docker-compose stop backend 2>/dev/null || true
docker-compose rm -f backend 2>/dev/null || true
docker rmi docker_backend 2>/dev/null || true
cd ..

echo -e "\n${GREEN}=== Fixes Applied Successfully! ===${NC}"
echo -e "${YELLOW}Now run:${NC}"
echo "  ./scripts/backend-start.sh"