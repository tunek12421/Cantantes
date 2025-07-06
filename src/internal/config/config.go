package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	App       AppConfig
	Database  DatabaseConfig
	Redis     RedisConfig
	MinIO     MinIOConfig
	JWT       JWTConfig
	SMS       SMSConfig
	RateLimit RateLimitConfig
}

type AppConfig struct {
	Env         string
	Port        string
	Version     string
	Debug       bool
	CORSOrigins string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

type RedisConfig struct {
	Host     string
	Port     string
	Password string
	DB       int
}

type MinIOConfig struct {
	Endpoint        string
	AccessKeyID     string
	SecretAccessKey string
	UseSSL          bool
	BucketMedia     string
	BucketThumbs    string
	BucketTemp      string
}

type JWTConfig struct {
	Secret               string
	AccessTokenDuration  time.Duration
	RefreshTokenDuration time.Duration
}

type SMSConfig struct {
	Provider   string // "twilio" or "mock"
	AccountSID string
	AuthToken  string
	FromNumber string
}

type RateLimitConfig struct {
	Requests int
	Window   time.Duration
}

func Load() *Config {
	return &Config{
		App: AppConfig{
			Env:         getEnv("APP_ENV", "development"),
			Port:        getEnv("APP_PORT", "8080"),
			Version:     getEnv("APP_VERSION", "1.0.0"),
			Debug:       getBoolEnv("APP_DEBUG", false),
			CORSOrigins: getEnv("CORS_ORIGINS", "http://localhost:3000"),
		},
		Database: DatabaseConfig{
			Host:     getEnv("POSTGRES_HOST", "postgres"),
			Port:     getEnv("POSTGRES_PORT", "5432"),
			User:     getEnv("POSTGRES_USER", "chat_user"),
			Password: getEnv("POSTGRES_PASSWORD", ""),
			DBName:   getEnv("POSTGRES_DB", "chat_e2ee"),
			SSLMode:  getEnv("POSTGRES_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Host:     getEnv("REDIS_HOST", "redis"),
			Port:     getEnv("REDIS_PORT", "6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getIntEnv("REDIS_DB", 0),
		},
		MinIO: MinIOConfig{
			Endpoint:        getEnv("MINIO_ENDPOINT", "minio:9000"),
			AccessKeyID:     getEnv("MINIO_ROOT_USER", ""),
			SecretAccessKey: getEnv("MINIO_ROOT_PASSWORD", ""),
			UseSSL:          getBoolEnv("MINIO_USE_SSL", false),
			BucketMedia:     getEnv("MINIO_BUCKET_MEDIA", "chat-media"),
			BucketThumbs:    getEnv("MINIO_BUCKET_THUMBS", "chat-thumbnails"),
			BucketTemp:      getEnv("MINIO_BUCKET_TEMP", "chat-temp"),
		},
		JWT: JWTConfig{
			Secret:               getEnv("JWT_SECRET", ""),
			AccessTokenDuration:  getDurationEnv("JWT_ACCESS_TOKEN_EXPIRE", "15m"),
			RefreshTokenDuration: getDurationEnv("JWT_REFRESH_TOKEN_EXPIRE", "7d"),
		},
		SMS: SMSConfig{
			Provider:   getEnv("SMS_PROVIDER", "mock"),
			AccountSID: getEnv("TWILIO_ACCOUNT_SID", ""),
			AuthToken:  getEnv("TWILIO_AUTH_TOKEN", ""),
			FromNumber: getEnv("TWILIO_PHONE_NUMBER", ""),
		},
		RateLimit: RateLimitConfig{
			Requests: getIntEnv("RATE_LIMIT_REQUESTS", 100),
			Window:   getDurationEnv("RATE_LIMIT_WINDOW", "1m"),
		},
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getBoolEnv(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		b, err := strconv.ParseBool(value)
		if err == nil {
			return b
		}
	}
	return defaultValue
}

func getIntEnv(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		i, err := strconv.Atoi(value)
		if err == nil {
			return i
		}
	}
	return defaultValue
}

func getDurationEnv(key string, defaultValue string) time.Duration {
	value := getEnv(key, defaultValue)

	// Handle simple formats like "7d" for 7 days
	if strings.HasSuffix(value, "d") {
		days := strings.TrimSuffix(value, "d")
		if d, err := strconv.Atoi(days); err == nil {
			return time.Duration(d) * 24 * time.Hour
		}
	}

	// Try standard duration parsing
	if duration, err := time.ParseDuration(value); err == nil {
		return duration
	}

	// Default to 15 minutes if parsing fails
	return 15 * time.Minute
}
