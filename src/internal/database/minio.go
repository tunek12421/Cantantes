package database

import (
	"context"
	"fmt"
	"log"

	"chat-e2ee/internal/config"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

func NewMinIOConnection(cfg config.MinIOConfig) (*minio.Client, error) {
	// Initialize MinIO client
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	// Create buckets if they don't exist
	ctx := context.Background()
	buckets := []string{cfg.BucketMedia, cfg.BucketThumbs, cfg.BucketTemp}

	for _, bucket := range buckets {
		exists, err := client.BucketExists(ctx, bucket)
		if err != nil {
			return nil, fmt.Errorf("failed to check bucket %s: %w", bucket, err)
		}

		if !exists {
			err = client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{})
			if err != nil {
				return nil, fmt.Errorf("failed to create bucket %s: %w", bucket, err)
			}
			log.Printf("Created bucket: %s", bucket)
		}
	}

	// Set bucket policies
	// Media and thumbnails should be publicly readable
	publicBuckets := []string{cfg.BucketMedia, cfg.BucketThumbs}
	for _, bucket := range publicBuckets {
		policy := fmt.Sprintf(`{
			"Version": "2012-10-17",
			"Statement": [{
				"Effect": "Allow",
				"Principal": {"AWS": ["*"]},
				"Action": ["s3:GetObject"],
				"Resource": ["arn:aws:s3:::%s/*"]
			}]
		}`, bucket)

		err = client.SetBucketPolicy(ctx, bucket, policy)
		if err != nil {
			log.Printf("Warning: Failed to set public policy for bucket %s: %v", bucket, err)
		}
	}

	return client, nil
}
