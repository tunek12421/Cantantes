package media

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"mime/multipart"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
)

// Service handles all media operations
type Service struct {
	db          *sql.DB
	minioClient *minio.Client
	bucketMedia string
	bucketThumb string
	bucketTemp  string
}

// NewService creates a new media service
func NewService(db *sql.DB, minioClient *minio.Client, bucketMedia, bucketThumb, bucketTemp string) *Service {
	return &Service{
		db:          db,
		minioClient: minioClient,
		bucketMedia: bucketMedia,
		bucketThumb: bucketThumb,
		bucketTemp:  bucketTemp,
	}
}

// UploadFile handles file upload to MinIO
func (s *Service) UploadFile(ctx context.Context, file multipart.File, header *multipart.FileHeader, userID string, mediaType string) (*MediaFile, error) {
	// Generate unique filename
	ext := filepath.Ext(header.Filename)
	objectName := fmt.Sprintf("%s/%s%s", userID, uuid.New().String(), ext)

	// Determine content type
	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	// Upload to MinIO
	info, err := s.minioClient.PutObject(ctx, s.bucketMedia, objectName, file, header.Size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to upload file: %w", err)
	}

	// Generate URL
	url := fmt.Sprintf("/api/v1/media/%s", info.Key)

	// Create media record
	media := &MediaFile{
		ID:               uuid.New().String(),
		UserID:           userID,
		Filename:         objectName,
		OriginalFilename: header.Filename,
		MimeType:         contentType,
		Size:             header.Size,
		Type:             mediaType,
		URL:              url,
		CreatedAt:        time.Now(),
	}

	// Save to database
	query := `
		INSERT INTO gallery_media (
			id, gallery_id, type, filename, original_filename, 
			mime_type, size_bytes, url, created_at
		) VALUES ($1, NULL, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`

	err = s.db.QueryRowContext(ctx, query,
		media.ID, media.Type, media.Filename, media.OriginalFilename,
		media.MimeType, media.Size, media.URL, media.CreatedAt,
	).Scan(&media.ID)

	if err != nil {
		// Cleanup MinIO on DB failure
		s.minioClient.RemoveObject(ctx, s.bucketMedia, objectName, minio.RemoveObjectOptions{})
		return nil, fmt.Errorf("failed to save media record: %w", err)
	}

	return media, nil
}

// GetFile retrieves a file from MinIO
func (s *Service) GetFile(ctx context.Context, mediaID string, userID string) (*MediaFile, io.ReadCloser, error) {
	// Get media info from database
	var media MediaFile
	query := `
		SELECT id, type, filename, original_filename, mime_type, size_bytes, url, created_at
		FROM gallery_media 
		WHERE id = $1`

	err := s.db.QueryRowContext(ctx, query, mediaID).Scan(
		&media.ID, &media.Type, &media.Filename, &media.OriginalFilename,
		&media.MimeType, &media.Size, &media.URL, &media.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, ErrMediaNotFound
		}
		return nil, nil, err
	}

	// Get object from MinIO
	object, err := s.minioClient.GetObject(ctx, s.bucketMedia, media.Filename, minio.GetObjectOptions{})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get object: %w", err)
	}

	return &media, object, nil
}

// DeleteFile removes a file from MinIO and database
func (s *Service) DeleteFile(ctx context.Context, mediaID string, userID string) error {
	// Get media info first
	var filename string
	query := `SELECT filename FROM gallery_media WHERE id = $1 --
		SELECT id FROM model_galleries WHERE model_id = $2
	)`

	err := s.db.QueryRowContext(ctx, query, mediaID, userID).Scan(&filename)
	if err != nil {
		if err == sql.ErrNoRows {
			return ErrMediaNotFound
		}
		return err
	}

	// Delete from database
	_, err = s.db.ExecContext(ctx, "DELETE FROM gallery_media WHERE id = $1", mediaID)
	if err != nil {
		return err
	}

	// Delete from MinIO
	err = s.minioClient.RemoveObject(ctx, s.bucketMedia, filename, minio.RemoveObjectOptions{})
	if err != nil {
		// Log error but don't fail
		return fmt.Errorf("failed to delete from storage: %w", err)
	}

	return nil
}

// CreatePresignedURL generates a temporary URL for direct access
func (s *Service) CreatePresignedURL(ctx context.Context, objectName string, expiry time.Duration) (string, error) {
	url, err := s.minioClient.PresignedGetObject(ctx, s.bucketMedia, objectName, expiry, nil)
	if err != nil {
		return "", err
	}
	return url.String(), nil
}

// CreateUploadURL generates a presigned URL for direct upload
func (s *Service) CreateUploadURL(ctx context.Context, objectName string, expiry time.Duration) (string, error) {
	url, err := s.minioClient.PresignedPutObject(ctx, s.bucketTemp, objectName, expiry)
	if err != nil {
		return "", err
	}
	return url.String(), nil
}

// ValidateFileType checks if the file type is allowed
func ValidateFileType(filename string, contentType string) error {
	ext := strings.ToLower(filepath.Ext(filename))

	// Allowed extensions
	allowedImages := map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true}
	allowedVideos := map[string]bool{".mp4": true, ".webm": true, ".mov": true}
	allowedAudio := map[string]bool{".mp3": true, ".wav": true, ".ogg": true, ".m4a": true}

	if allowedImages[ext] || allowedVideos[ext] || allowedAudio[ext] {
		return nil
	}

	return ErrInvalidFileType
}

// GetMediaType returns the media type based on mime type
func GetMediaType(mimeType string) string {
	if strings.HasPrefix(mimeType, "image/") {
		return "photo"
	}
	if strings.HasPrefix(mimeType, "video/") {
		return "video"
	}
	if strings.HasPrefix(mimeType, "audio/") {
		return "audio"
	}
	return "file"
}
