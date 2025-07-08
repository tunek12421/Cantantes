package media

import (
	"errors"
	"time"
)

// Common errors
var (
	ErrMediaNotFound   = errors.New("media not found")
	ErrInvalidFileType = errors.New("invalid file type")
	ErrFileTooLarge    = errors.New("file too large")
	ErrGalleryNotFound = errors.New("gallery not found")
	ErrUnauthorized    = errors.New("unauthorized access")
)

// MediaFile represents a media file
type MediaFile struct {
	ID               string                 `json:"id"`
	GalleryID        *string                `json:"gallery_id,omitempty"`
	UserID           string                 `json:"user_id"`
	Type             string                 `json:"type"` // photo, video, audio
	Filename         string                 `json:"filename"`
	OriginalFilename string                 `json:"original_filename"`
	MimeType         string                 `json:"mime_type"`
	Size             int64                  `json:"size"`
	Width            *int                   `json:"width,omitempty"`
	Height           *int                   `json:"height,omitempty"`
	Duration         *int                   `json:"duration,omitempty"`
	ThumbnailURL     *string                `json:"thumbnail_url,omitempty"`
	URL              string                 `json:"url"`
	Hash             *string                `json:"hash,omitempty"`
	IsPublic         bool                   `json:"is_public"`
	CreatedAt        time.Time              `json:"created_at"`
	Metadata         map[string]interface{} `json:"metadata,omitempty"`
}

// Gallery represents a model's media gallery
type Gallery struct {
	ID         string                 `json:"id"`
	ModelID    string                 `json:"model_id"`
	CreatedAt  time.Time              `json:"created_at"`
	UpdatedAt  time.Time              `json:"updated_at"`
	TotalSize  int64                  `json:"total_size_bytes"`
	MediaCount int                    `json:"media_count"`
	Settings   map[string]interface{} `json:"settings,omitempty"`
}

// UploadRequest represents a file upload request
type UploadRequest struct {
	Type        string `json:"type" validate:"required,oneof=photo video audio"`
	GalleryID   string `json:"gallery_id,omitempty"`
	IsPublic    bool   `json:"is_public"`
	Description string `json:"description,omitempty"`
}

// UploadResponse represents the response after upload
type UploadResponse struct {
	ID           string `json:"id"`
	URL          string `json:"url"`
	ThumbnailURL string `json:"thumbnail_url,omitempty"`
	Type         string `json:"type"`
	Size         int64  `json:"size"`
}

// GalleryListResponse represents a paginated list of gallery items
type GalleryListResponse struct {
	Items      []*MediaFile `json:"items"`
	TotalCount int          `json:"total_count"`
	TotalSize  int64        `json:"total_size"`
	Page       int          `json:"page"`
	PageSize   int          `json:"page_size"`
	HasMore    bool         `json:"has_more"`
}

// MediaFilters for querying media
type MediaFilters struct {
	Type      string    `query:"type"`
	IsPublic  *bool     `query:"is_public"`
	StartDate time.Time `query:"start_date"`
	EndDate   time.Time `query:"end_date"`
	Page      int       `query:"page"`
	PageSize  int       `query:"page_size"`
}

// Constants
const (
	MaxFileSize      = 100 * 1024 * 1024 // 100MB
	MaxImageSize     = 20 * 1024 * 1024  // 20MB
	MaxVideoSize     = 100 * 1024 * 1024 // 100MB
	MaxAudioSize     = 50 * 1024 * 1024  // 50MB
	DefaultPageSize  = 20
	MaxPageSize      = 100
	ThumbnailWidth   = 400
	ThumbnailHeight  = 400
	ThumbnailQuality = 80
)
