package media

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"strings"

	"github.com/disintegration/imaging"
	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
)

// ThumbnailService handles thumbnail generation
type ThumbnailService struct {
	minioClient *minio.Client
	bucketThumb string
	bucketMedia string
}

// NewThumbnailService creates a new thumbnail service
func NewThumbnailService(minioClient *minio.Client, bucketThumb, bucketMedia string) *ThumbnailService {
	return &ThumbnailService{
		minioClient: minioClient,
		bucketThumb: bucketThumb,
		bucketMedia: bucketMedia,
	}
}

// GenerateThumbnail creates a thumbnail for an image
func (s *ThumbnailService) GenerateThumbnail(ctx context.Context, objectName string) (string, error) {
	// Get original image from MinIO
	object, err := s.minioClient.GetObject(ctx, s.bucketMedia, objectName, minio.GetObjectOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to get original image: %w", err)
	}
	defer object.Close()

	// Decode image
	img, format, err := image.Decode(object)
	if err != nil {
		return "", fmt.Errorf("failed to decode image: %w", err)
	}

	// Generate thumbnail
	thumbnail := imaging.Thumbnail(img, ThumbnailWidth, ThumbnailHeight, imaging.Lanczos)

	// Encode thumbnail
	var buf bytes.Buffer
	switch format {
	case "jpeg", "jpg":
		err = jpeg.Encode(&buf, thumbnail, &jpeg.Options{Quality: ThumbnailQuality})
	case "png":
		err = png.Encode(&buf, thumbnail)
	default:
		// Default to JPEG for other formats
		err = jpeg.Encode(&buf, thumbnail, &jpeg.Options{Quality: ThumbnailQuality})
		format = "jpeg"
	}

	if err != nil {
		return "", fmt.Errorf("failed to encode thumbnail: %w", err)
	}

	// Generate thumbnail filename
	thumbName := fmt.Sprintf("thumb_%s.%s", uuid.New().String(), format)

	// Upload thumbnail to MinIO
	_, err = s.minioClient.PutObject(ctx, s.bucketThumb, thumbName, &buf, int64(buf.Len()), minio.PutObjectOptions{
		ContentType: fmt.Sprintf("image/%s", format),
	})
	if err != nil {
		return "", fmt.Errorf("failed to upload thumbnail: %w", err)
	}

	// Return thumbnail URL
	return fmt.Sprintf("/api/v1/media/thumbnail/%s", thumbName), nil
}

// GetThumbnail retrieves a thumbnail
func (s *ThumbnailService) GetThumbnail(ctx context.Context, thumbName string) (io.ReadCloser, string, error) {
	// Get thumbnail from MinIO
	object, err := s.minioClient.GetObject(ctx, s.bucketThumb, thumbName, minio.GetObjectOptions{})
	if err != nil {
		return nil, "", err
	}

	// Determine content type
	contentType := "image/jpeg"
	if strings.HasSuffix(thumbName, ".png") {
		contentType = "image/png"
	}

	return object, contentType, nil
}

// GenerateVideoThumbnail creates a thumbnail for a video (placeholder for now)
func (s *ThumbnailService) GenerateVideoThumbnail(ctx context.Context, objectName string) (string, error) {
	// TODO: Implement video thumbnail generation using ffmpeg
	// For now, return a default video thumbnail
	return "/assets/default-video-thumb.jpg", nil
}

// CleanupOrphanedThumbnails removes thumbnails without corresponding media
func (s *ThumbnailService) CleanupOrphanedThumbnails(ctx context.Context) error {
	// List all objects in thumbnail bucket
	objectCh := s.minioClient.ListObjects(ctx, s.bucketThumb, minio.ListObjectsOptions{
		Recursive: true,
	})

	for object := range objectCh {
		if object.Err != nil {
			continue
		}

		// TODO: Check if corresponding media exists in database
		// If not, delete the thumbnail
	}

	return nil
}
