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
// FIXED: This was rejecting unauthenticated requests
func OptionalAuthMiddleware(jwtService *JWTService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Get authorization header
		authHeader := c.Get("Authorization")

		// If no auth header, that's fine - continue without authentication
		if authHeader == "" {
			// Set authenticated to false so handlers know
			c.Locals("authenticated", false)
			return c.Next()
		}

		// Check Bearer prefix
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			// Invalid format, but continue without auth for optional endpoints
			c.Locals("authenticated", false)
			return c.Next()
		}

		// Validate token
		token := parts[1]
		claims, err := jwtService.ValidateToken(token)
		if err != nil {
			// Token is invalid, but that's OK for optional auth
			// Just continue without authentication
			c.Locals("authenticated", false)
			return c.Next()
		}

		// Check token type
		if claims.Type != "access" {
			// Wrong token type, continue without auth
			c.Locals("authenticated", false)
			return c.Next()
		}

		// Valid token found! Store user info
		c.Locals("userID", claims.UserID)
		c.Locals("deviceID", claims.DeviceID)
		c.Locals("authenticated", true)

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

// IsAuthenticated helper function to check if request is authenticated
func IsAuthenticated(c *fiber.Ctx) bool {
	authenticated, ok := c.Locals("authenticated").(bool)
	return ok && authenticated
}

// GetUserID helper function to safely get user ID
func GetUserID(c *fiber.Ctx) (string, bool) {
	userID, ok := c.Locals("userID").(string)
	return userID, ok
}

// GetDeviceID helper function to safely get device ID
func GetDeviceID(c *fiber.Ctx) (string, bool) {
	deviceID, ok := c.Locals("deviceID").(string)
	return deviceID, ok
}
