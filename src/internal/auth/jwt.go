package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrExpiredToken = errors.New("expired token")
)

type JWTService struct {
	secret               string
	accessTokenDuration  time.Duration
	refreshTokenDuration time.Duration
}

type Claims struct {
	UserID   string `json:"user_id"`
	DeviceID string `json:"device_id"`
	Type     string `json:"type"` // "access" or "refresh"
	jwt.RegisteredClaims
}

func NewJWTService(secret string, accessDuration, refreshDuration time.Duration) *JWTService {
	return &JWTService{
		secret:               secret,
		accessTokenDuration:  accessDuration,
		refreshTokenDuration: refreshDuration,
	}
}

// GenerateTokenPair generates both access and refresh tokens
func (j *JWTService) GenerateTokenPair(userID, deviceID string) (accessToken, refreshToken string, err error) {
	// Generate access token
	accessToken, err = j.generateToken(userID, deviceID, "access", j.accessTokenDuration)
	if err != nil {
		return "", "", err
	}

	// Generate refresh token
	refreshToken, err = j.generateToken(userID, deviceID, "refresh", j.refreshTokenDuration)
	if err != nil {
		return "", "", err
	}

	return accessToken, refreshToken, nil
}

// generateToken creates a single token
func (j *JWTService) generateToken(userID, deviceID, tokenType string, duration time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID:   userID,
		DeviceID: deviceID,
		Type:     tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(duration)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(j.secret))
}

// ValidateToken validates and parses a token
func (j *JWTService) ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(j.secret), nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	// Check expiration
	if claims.ExpiresAt != nil && claims.ExpiresAt.Before(time.Now()) {
		return nil, ErrExpiredToken
	}

	return claims, nil
}

// RefreshAccessToken generates a new access token from a valid refresh token
func (j *JWTService) RefreshAccessToken(refreshToken string) (string, error) {
	claims, err := j.ValidateToken(refreshToken)
	if err != nil {
		return "", err
	}

	// Verify this is a refresh token
	if claims.Type != "refresh" {
		return "", errors.New("not a refresh token")
	}

	// Generate new access token
	accessToken, err := j.generateToken(claims.UserID, claims.DeviceID, "access", j.accessTokenDuration)
	if err != nil {
		return "", err
	}

	return accessToken, nil
}
