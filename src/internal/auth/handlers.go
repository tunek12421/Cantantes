package auth

import (
	"context"
	"database/sql"
	"log"
	"regexp"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	db           *sql.DB
	jwtService   *JWTService
	smsService   *SMSService
	sessionStore *SessionStore
}

func NewAuthHandler(db *sql.DB, jwtService *JWTService, smsService *SMSService, sessionStore *SessionStore) *AuthHandler {
	return &AuthHandler{
		db:           db,
		jwtService:   jwtService,
		smsService:   smsService,
		sessionStore: sessionStore,
	}
}

// RequestOTP handles OTP request
func (h *AuthHandler) RequestOTP(c *fiber.Ctx) error {
	var req struct {
		PhoneNumber string `json:"phone_number" validate:"required"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Validate phone number format
	phoneRegex := regexp.MustCompile(`^\+?[1-9]\d{1,14}$`)
	if !phoneRegex.MatchString(req.PhoneNumber) {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid phone number format",
		})
	}

	// Send OTP
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := h.smsService.SendOTP(ctx, req.PhoneNumber); err != nil {
		log.Printf("Failed to send OTP to %s: %v", req.PhoneNumber, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to send OTP",
		})
	}

	return c.JSON(fiber.Map{
		"message": "OTP sent successfully",
		"phone":   req.PhoneNumber,
	})
}

// VerifyOTP handles OTP verification and returns JWT tokens
func (h *AuthHandler) VerifyOTP(c *fiber.Ctx) error {
	var req struct {
		PhoneNumber string `json:"phone_number" validate:"required"`
		OTP         string `json:"otp" validate:"required,len=6"`
		DeviceID    string `json:"device_id" validate:"required"`
		DeviceName  string `json:"device_name"`
		PublicKey   string `json:"public_key" validate:"required"` // For E2EE
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Verify OTP
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := h.smsService.VerifyOTP(ctx, req.PhoneNumber, req.OTP); err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	// Get or create user
	userID, isNewUser, err := h.getOrCreateUser(ctx, req.PhoneNumber)
	if err != nil {
		log.Printf("Failed to get/create user: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to process user",
		})
	}

	// Register device
	if err := h.registerDevice(ctx, userID, req.DeviceID, req.DeviceName, req.PublicKey); err != nil {
		log.Printf("Failed to register device: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to register device",
		})
	}

	// Generate JWT tokens
	accessToken, refreshToken, err := h.jwtService.GenerateTokenPair(userID, req.DeviceID)
	if err != nil {
		log.Printf("Failed to generate tokens: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to generate tokens",
		})
	}

	// Store session
	sessionData := map[string]string{
		"user_id":   userID,
		"device_id": req.DeviceID,
		"phone":     req.PhoneNumber,
	}
	h.sessionStore.StoreSession(ctx, refreshToken, sessionData, 7*24*time.Hour)

	return c.JSON(fiber.Map{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"user_id":       userID,
		"is_new_user":   isNewUser,
	})
}

// RefreshToken handles token refresh
func (h *AuthHandler) RefreshToken(c *fiber.Ctx) error {
	var req struct {
		RefreshToken string `json:"refresh_token" validate:"required"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Validate refresh token
	claims, err := h.jwtService.ValidateToken(req.RefreshToken)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid refresh token",
		})
	}

	if claims.Type != "refresh" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Not a refresh token",
		})
	}

	// Check if session exists
	ctx := context.Background()
	session, err := h.sessionStore.GetSession(ctx, req.RefreshToken)
	if err != nil || len(session) == 0 {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Session not found",
		})
	}

	// Generate new access token
	accessToken, err := h.jwtService.RefreshAccessToken(req.RefreshToken)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to refresh token",
		})
	}

	// Extend session
	h.sessionStore.ExtendSession(ctx, req.RefreshToken, 7*24*time.Hour)

	return c.JSON(fiber.Map{
		"access_token": accessToken,
	})
}

// Logout handles user logout
func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	// Get refresh token from request
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Delete session
	if req.RefreshToken != "" {
		ctx := context.Background()
		h.sessionStore.DeleteSession(ctx, req.RefreshToken)
	}

	// Update user last seen
	userID := c.Locals("userID").(string)
	if userID != "" {
		h.updateLastSeen(context.Background(), userID)
	}

	return c.JSON(fiber.Map{
		"message": "Logged out successfully",
	})
}

// Helper functions

func (h *AuthHandler) getOrCreateUser(ctx context.Context, phoneNumber string) (string, bool, error) {
	var userID string
	var isNew bool

	// Check if user exists
	err := h.db.QueryRowContext(ctx,
		"SELECT id FROM users WHERE phone_number = $1",
		phoneNumber,
	).Scan(&userID)

	if err == sql.ErrNoRows {
		// Create new user
		userID = uuid.New().String()
		_, err = h.db.ExecContext(ctx,
			`INSERT INTO users (id, phone_number, created_at, updated_at) 
			VALUES ($1, $2, NOW(), NOW())`,
			userID, phoneNumber,
		)
		if err != nil {
			return "", false, err
		}
		isNew = true
	} else if err != nil {
		return "", false, err
	}

	return userID, isNew, nil
}

func (h *AuthHandler) registerDevice(ctx context.Context, userID, deviceID, deviceName, publicKey string) error {
	platform := "web" // Default, could be detected from user agent

	_, err := h.db.ExecContext(ctx,
		`INSERT INTO user_devices (id, user_id, device_id, name, platform, public_key, created_at) 
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
		ON CONFLICT (device_id) 
		DO UPDATE SET public_key = $6, last_active = NOW()`,
		uuid.New().String(), userID, deviceID, deviceName, platform, publicKey,
	)
	return err
}

func (h *AuthHandler) updateLastSeen(ctx context.Context, userID string) {
	_, err := h.db.ExecContext(ctx,
		"UPDATE users SET last_seen = NOW() WHERE id = $1",
		userID,
	)
	if err != nil {
		log.Printf("Failed to update last seen for user %s: %v", userID, err)
	}
}
