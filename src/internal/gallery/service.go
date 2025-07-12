package gallery

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Service handles gallery operations
type Service struct {
	DB *sql.DB
}

// NewService creates a new gallery service
func NewService(db *sql.DB) *Service {
	return &Service{DB: db}
}

// CreateGallery creates a new gallery for a model
func (s *Service) CreateGallery(ctx context.Context, modelID string) (*Gallery, error) {
	gallery := &Gallery{
		ID:        uuid.New().String(),
		ModelID:   modelID,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		Settings:  make(map[string]interface{}),
	}

	query := `
		INSERT INTO model_galleries (id, model_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (model_id) DO UPDATE
		SET updated_at = $4
		RETURNING id, created_at`

	err := s.DB.QueryRowContext(ctx, query,
		gallery.ID, gallery.ModelID, gallery.CreatedAt, gallery.UpdatedAt,
	).Scan(&gallery.ID, &gallery.CreatedAt)

	if err != nil {
		return nil, fmt.Errorf("failed to create gallery: %w", err)
	}

	return gallery, nil
}

// GetGallery retrieves a gallery by model ID
func (s *Service) GetGallery(ctx context.Context, modelID string) (*Gallery, error) {
	var gallery Gallery

	query := `
		SELECT id, model_id, created_at, updated_at, 
		       total_size_bytes, media_count
		FROM model_galleries
		WHERE model_id = $1`

	err := s.DB.QueryRowContext(ctx, query, modelID).Scan(
		&gallery.ID, &gallery.ModelID, &gallery.CreatedAt,
		&gallery.UpdatedAt, &gallery.TotalSize, &gallery.MediaCount,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrGalleryNotFound
		}
		return nil, err
	}

	return &gallery, nil
}

// GetGalleryMedia retrieves media items from a gallery
func (s *Service) GetGalleryMedia(ctx context.Context, galleryID string, filters *MediaFilters) ([]*MediaFile, int, error) {
	// Build query
	query := `
		SELECT id, gallery_id, type, filename, original_filename,
		       mime_type, size_bytes, width, height, duration_seconds,
		       thumbnail_url, url, is_public, created_at
		FROM gallery_media
		WHERE gallery_id = $1`

	countQuery := `SELECT COUNT(*) FROM gallery_media WHERE gallery_id = $1`

	args := []interface{}{galleryID}
	countArgs := []interface{}{galleryID}
	argCount := 1

	// Apply filters
	if filters.Type != "" {
		argCount++
		query += fmt.Sprintf(" AND type = $%d", argCount)
		countQuery += fmt.Sprintf(" AND type = $%d", argCount)
		args = append(args, filters.Type)
		countArgs = append(countArgs, filters.Type)
	}

	if filters.IsPublic != nil {
		argCount++
		query += fmt.Sprintf(" AND is_public = $%d", argCount)
		countQuery += fmt.Sprintf(" AND is_public = $%d", argCount)
		args = append(args, *filters.IsPublic)
		countArgs = append(countArgs, *filters.IsPublic)
	}

	// Add ordering and pagination
	query += " ORDER BY created_at DESC"

	if filters.PageSize > 0 {
		offset := (filters.Page - 1) * filters.PageSize
		query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argCount+1, argCount+2)
		args = append(args, filters.PageSize, offset)
	}

	// Get total count
	var totalCount int
	err := s.DB.QueryRowContext(ctx, countQuery, countArgs...).Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	// Get media items
	rows, err := s.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]*MediaFile, 0)
	for rows.Next() {
		var item MediaFile
		err := rows.Scan(
			&item.ID, &item.GalleryID, &item.Type, &item.Filename,
			&item.OriginalFilename, &item.MimeType, &item.Size,
			&item.Width, &item.Height, &item.Duration,
			&item.ThumbnailURL, &item.URL, &item.IsPublic,
			&item.CreatedAt,
		)
		if err != nil {
			continue
		}
		items = append(items, &item)
	}

	return items, totalCount, nil
}

// UpdateGallerySettings updates gallery settings
func (s *Service) UpdateGallerySettings(ctx context.Context, galleryID string, settings map[string]interface{}) error {
	// Convert settings to JSON
	settingsJSON, err := json.Marshal(settings)
	if err != nil {
		return err
	}

	query := `
		UPDATE model_galleries
		SET settings = $1, updated_at = NOW()
		WHERE id = $2`

	_, err = s.DB.ExecContext(ctx, query, settingsJSON, galleryID)
	return err
}

// GetModelGalleries retrieves all galleries for models (for discovery)
func (s *Service) GetModelGalleries(ctx context.Context, limit, offset int) ([]*GalleryPreview, error) {
	query := `
		SELECT g.id, g.model_id, g.media_count, g.updated_at,
		       u.username, u.display_name, u.avatar_url,
		       (SELECT url FROM gallery_media 
		        WHERE gallery_id = g.id AND is_public = true 
		        ORDER BY created_at DESC LIMIT 1) as preview_url
		FROM model_galleries g
		JOIN users u ON u.id = g.model_id
		WHERE u.role = 'model' AND u.status = 'active'
		  AND g.media_count > 0
		ORDER BY g.updated_at DESC
		LIMIT $1 OFFSET $2`

	rows, err := s.DB.QueryContext(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	galleries := make([]*GalleryPreview, 0)
	for rows.Next() {
		var preview GalleryPreview
		err := rows.Scan(
			&preview.GalleryID, &preview.ModelID, &preview.MediaCount,
			&preview.UpdatedAt, &preview.Username, &preview.DisplayName,
			&preview.AvatarURL, &preview.PreviewURL,
		)
		if err != nil {
			continue
		}
		galleries = append(galleries, &preview)
	}

	return galleries, nil
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

// GalleryPreview for model discovery
type GalleryPreview struct {
	GalleryID   string    `json:"gallery_id"`
	ModelID     string    `json:"model_id"`
	Username    string    `json:"username"`
	DisplayName *string   `json:"display_name"`
	AvatarURL   *string   `json:"avatar_url"`
	MediaCount  int       `json:"media_count"`
	PreviewURL  *string   `json:"preview_url"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// MediaFile represents a media file in a gallery
type MediaFile struct {
	ID               string    `json:"id"`
	GalleryID        *string   `json:"gallery_id,omitempty"`
	Type             string    `json:"type"`
	Filename         string    `json:"filename"`
	OriginalFilename string    `json:"original_filename"`
	MimeType         string    `json:"mime_type"`
	Size             int64     `json:"size"`
	Width            *int      `json:"width,omitempty"`
	Height           *int      `json:"height,omitempty"`
	Duration         *int      `json:"duration,omitempty"`
	ThumbnailURL     *string   `json:"thumbnail_url,omitempty"`
	URL              string    `json:"url"`
	IsPublic         bool      `json:"is_public"`
	CreatedAt        time.Time `json:"created_at"`
}

// MediaFilters for querying media
type MediaFilters struct {
	Type     string `query:"type"`
	IsPublic *bool  `query:"is_public"`
	Page     int    `query:"page"`
	PageSize int    `query:"page_size"`
}
