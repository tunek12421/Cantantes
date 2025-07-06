package auth

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"time"
)

// SMSProvider interface allows for different SMS providers
type SMSProvider interface {
	SendSMS(ctx context.Context, to, message string) error
}

// MockSMSProvider for development/testing
type MockSMSProvider struct{}

func (m *MockSMSProvider) SendSMS(ctx context.Context, to, message string) error {
	log.Printf("[MOCK SMS] To: %s, Message: %s", to, message)
	return nil
}

// TwilioProvider for production use
type TwilioProvider struct {
	accountSID string
	authToken  string
	fromNumber string
	// In production, you'd use the Twilio Go SDK here
}

func NewTwilioProvider(accountSID, authToken, fromNumber string) *TwilioProvider {
	return &TwilioProvider{
		accountSID: accountSID,
		authToken:  authToken,
		fromNumber: fromNumber,
	}
}

func (t *TwilioProvider) SendSMS(ctx context.Context, to, message string) error {
	// TODO: Implement actual Twilio integration
	// For now, just log
	log.Printf("[TWILIO] Would send SMS to %s: %s", to, message)
	return nil
}

// SMSService handles OTP generation and verification
type SMSService struct {
	provider     SMSProvider
	otpStore     OTPStore
	otpLength    int
	otpExpiryMin int
}

// OTPStore interface for storing OTPs (Redis implementation)
type OTPStore interface {
	SetOTP(ctx context.Context, phone, otp string, expiry time.Duration) error
	GetOTP(ctx context.Context, phone string) (string, error)
	DeleteOTP(ctx context.Context, phone string) error
	IncrementAttempts(ctx context.Context, phone string) (int, error)
}

func NewSMSService(provider SMSProvider, store OTPStore) *SMSService {
	return &SMSService{
		provider:     provider,
		otpStore:     store,
		otpLength:    6,
		otpExpiryMin: 5, // OTP expires in 5 minutes
	}
}

// GenerateOTP creates a random numeric OTP
func (s *SMSService) GenerateOTP() (string, error) {
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(s.otpLength)), nil)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}

	// Pad with zeros if necessary
	format := fmt.Sprintf("%%0%dd", s.otpLength)
	return fmt.Sprintf(format, n), nil
}

// SendOTP generates and sends an OTP to the phone number
func (s *SMSService) SendOTP(ctx context.Context, phoneNumber string) error {
	// Check rate limiting (max 3 OTPs per hour)
	attempts, err := s.otpStore.IncrementAttempts(ctx, "attempts:"+phoneNumber)
	if err == nil && attempts > 3 {
		return fmt.Errorf("too many OTP requests, please try again later")
	}

	// Generate OTP
	otp, err := s.GenerateOTP()
	if err != nil {
		return fmt.Errorf("failed to generate OTP: %w", err)
	}

	// Store OTP with expiry
	expiry := time.Duration(s.otpExpiryMin) * time.Minute
	if err := s.otpStore.SetOTP(ctx, phoneNumber, otp, expiry); err != nil {
		return fmt.Errorf("failed to store OTP: %w", err)
	}

	// Send SMS
	message := fmt.Sprintf("Your Chat E2EE verification code is: %s\nValid for %d minutes.", otp, s.otpExpiryMin)
	if err := s.provider.SendSMS(ctx, phoneNumber, message); err != nil {
		// Delete OTP if SMS fails
		_ = s.otpStore.DeleteOTP(ctx, phoneNumber)
		return fmt.Errorf("failed to send SMS: %w", err)
	}

	return nil
}

// VerifyOTP checks if the provided OTP is valid
func (s *SMSService) VerifyOTP(ctx context.Context, phoneNumber, otp string) error {
	// Get stored OTP
	storedOTP, err := s.otpStore.GetOTP(ctx, phoneNumber)
	if err != nil {
		return fmt.Errorf("OTP not found or expired")
	}

	// Compare OTPs
	if storedOTP != otp {
		return fmt.Errorf("invalid OTP")
	}

	// Delete OTP after successful verification
	if err := s.otpStore.DeleteOTP(ctx, phoneNumber); err != nil {
		log.Printf("Failed to delete OTP for %s: %v", phoneNumber, err)
	}

	// Clear rate limit attempts on successful verification
	_ = s.otpStore.DeleteOTP(ctx, "attempts:"+phoneNumber)

	return nil
}
