package auth

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisOTPStore implements OTPStore using Redis
type RedisOTPStore struct {
	client *redis.Client
}

func NewRedisOTPStore(client *redis.Client) *RedisOTPStore {
	return &RedisOTPStore{client: client}
}

// SetOTP stores an OTP with expiration
func (r *RedisOTPStore) SetOTP(ctx context.Context, phone, otp string, expiry time.Duration) error {
	key := fmt.Sprintf("otp:%s", phone)
	return r.client.Set(ctx, key, otp, expiry).Err()
}

// GetOTP retrieves an OTP
func (r *RedisOTPStore) GetOTP(ctx context.Context, phone string) (string, error) {
	key := fmt.Sprintf("otp:%s", phone)
	val, err := r.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", fmt.Errorf("OTP not found")
	}
	return val, err
}

// DeleteOTP removes an OTP
func (r *RedisOTPStore) DeleteOTP(ctx context.Context, phone string) error {
	key := fmt.Sprintf("otp:%s", phone)
	return r.client.Del(ctx, key).Err()
}

// IncrementAttempts increments and returns the attempt count
func (r *RedisOTPStore) IncrementAttempts(ctx context.Context, phone string) (int, error) {
	key := fmt.Sprintf("otp_attempts:%s", phone)

	// Increment the counter
	val, err := r.client.Incr(ctx, key).Result()
	if err != nil {
		return 0, err
	}

	// Set expiration on first attempt (1 hour window)
	if val == 1 {
		r.client.Expire(ctx, key, time.Hour)
	}

	return int(val), nil
}

// SessionStore manages user sessions in Redis
type SessionStore struct {
	client *redis.Client
}

func NewSessionStore(client *redis.Client) *SessionStore {
	return &SessionStore{client: client}
}

// StoreSession saves session data
func (s *SessionStore) StoreSession(ctx context.Context, sessionID string, data map[string]string, expiry time.Duration) error {
	key := fmt.Sprintf("session:%s", sessionID)

	// Convert map to Redis hash
	args := make([]interface{}, 0, len(data)*2)
	for k, v := range data {
		args = append(args, k, v)
	}

	// Store hash
	if err := s.client.HSet(ctx, key, args...).Err(); err != nil {
		return err
	}

	// Set expiration
	return s.client.Expire(ctx, key, expiry).Err()
}

// GetSession retrieves session data
func (s *SessionStore) GetSession(ctx context.Context, sessionID string) (map[string]string, error) {
	key := fmt.Sprintf("session:%s", sessionID)
	return s.client.HGetAll(ctx, key).Result()
}

// DeleteSession removes a session
func (s *SessionStore) DeleteSession(ctx context.Context, sessionID string) error {
	key := fmt.Sprintf("session:%s", sessionID)
	return s.client.Del(ctx, key).Err()
}

// ExtendSession updates the expiration time
func (s *SessionStore) ExtendSession(ctx context.Context, sessionID string, expiry time.Duration) error {
	key := fmt.Sprintf("session:%s", sessionID)
	return s.client.Expire(ctx, key, expiry).Err()
}
