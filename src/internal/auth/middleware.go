package auth

import (
	"strings"

	"github.com/gofiber/fiber/v2"
)

// AuthMiddleware creates a middleware function for JWT authentication
func AuthMiddleware(jwtService *JWTService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Get authorization header
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Missing authorization header",
			})
		}

		// Check Bearer prefix
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid authorization format",
			})
		}

		// Validate token
		token := parts[1]
		claims, err := jwtService.ValidateToken(token)
		if err != nil {
			if err == ErrExpiredToken {
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Token expired",
					"code":  "TOKEN_EXPIRED",
				})
			}
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid token",
			})
		}

		// Check token type
		if claims.Type != "access" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid token type",
			})
		}

		// Store user info in context
		c.Locals("userID", claims.UserID)
		c.Locals("deviceID", claims.DeviceID)

		return c.Next()
	}
}

// OptionalAuthMiddleware allows requests with or without authentication
func OptionalAuthMiddleware(jwtService *JWTService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Get authorization header
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			// No auth header is OK for optional auth
			return c.Next()
		}

		// Check Bearer prefix
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			// Invalid format, but continue without auth
			return c.Next()
		}

		// Validate token
		token := parts[1]
		claims, err := jwtService.ValidateToken(token)
		if err == nil && claims.Type == "access" {
			// Valid token, store user info
			c.Locals("userID", claims.UserID)
			c.Locals("deviceID", claims.DeviceID)
		}

		// Continue regardless of token validity
		return c.Next()
	}
}

// RequireRole middleware checks if user has required role
func RequireRole(requiredRole string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// This would typically check the user's role from database
		// For now, we'll implement basic structure
		userID := c.Locals("userID")
		if userID == nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Authentication required",
			})
		}

		// TODO: Fetch user role from database and check
		// For now, just pass through
		return c.Next()
	}
}

// RateLimitMiddleware for auth endpoints
func RateLimitMiddleware(maxAttempts int) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// TODO: Implement rate limiting using Redis
		// Track by IP address or phone number
		return c.Next()
	}
}
