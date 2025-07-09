package discovery

import (
	"time"
)

// ModelProfileResponse represents a detailed model profile
type ModelProfileResponse struct {
	ID          string                 `json:"id"`
	Username    *string                `json:"username,omitempty"`
	DisplayName *string                `json:"display_name,omitempty"`
	AvatarURL   *string                `json:"avatar_url,omitempty"`
	Status      string                 `json:"status"`
	IsOnline    bool                   `json:"is_online"`
	LastSeen    time.Time              `json:"last_seen"`
	CreatedAt   time.Time              `json:"created_at"`
	Gallery     *ModelGalleryInfo      `json:"gallery,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// ModelGalleryInfo represents gallery information for a model
type ModelGalleryInfo struct {
	GalleryID   string         `json:"gallery_id"`
	MediaCount  int            `json:"media_count"`
	TotalSize   int64          `json:"total_size_bytes"`
	UpdatedAt   time.Time      `json:"updated_at"`
	PreviewURL  *string        `json:"preview_url,omitempty"`
	SampleMedia []*SampleMedia `json:"sample_media,omitempty"`
}

// SampleMedia represents a sample from the gallery
type SampleMedia struct {
	URL          string  `json:"url"`
	ThumbnailURL *string `json:"thumbnail_url,omitempty"`
	Type         string  `json:"type"` // photo, video, audio
}

// FeaturedModels represents different categories of featured models
type FeaturedModels struct {
	Popular []*ModelSummary `json:"popular"`
	New     []*ModelSummary `json:"new"`
	Online  []*ModelSummary `json:"online"`
}

// ModelSummary represents a summary view of a model
type ModelSummary struct {
	ID          string  `json:"id"`
	Username    *string `json:"username,omitempty"`
	DisplayName *string `json:"display_name,omitempty"`
	AvatarURL   *string `json:"avatar_url,omitempty"`
	IsOnline    bool    `json:"is_online"`
	MediaCount  int     `json:"media_count"`
	PreviewURL  *string `json:"preview_url,omitempty"`
}

// DiscoveryFilters for advanced model search
type DiscoveryFilters struct {
	Search     string   `query:"search"`
	Tags       []string `query:"tags"`
	Languages  []string `query:"languages"`
	OnlineOnly bool     `query:"online_only"`
	HasGallery bool     `query:"has_gallery"`
	MinMedia   int      `query:"min_media"`
	SortBy     string   `query:"sort_by"`
	Page       int      `query:"page"`
	PageSize   int      `query:"page_size"`
}

// ModelStats represents statistics about models
type ModelStats struct {
	TotalModels  int       `json:"total_models"`
	OnlineModels int       `json:"online_models"`
	ActiveToday  int       `json:"active_today"`
	NewThisWeek  int       `json:"new_this_week"`
	TotalMedia   int       `json:"total_media"`
	UpdatedAt    time.Time `json:"updated_at"`
}
