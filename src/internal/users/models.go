package users

import (
	"time"
)

// User represents a user in the system
type User struct {
	ID          string                 `json:"id"`
	PhoneNumber string                 `json:"phone_number"`
	Username    *string                `json:"username,omitempty"`
	DisplayName *string                `json:"display_name,omitempty"`
	AvatarURL   *string                `json:"avatar_url,omitempty"`
	Role        string                 `json:"role"`   // user, model, admin
	Status      string                 `json:"status"` // active, inactive, suspended, deleted
	IsOnline    bool                   `json:"is_online"`
	LastSeen    time.Time              `json:"last_seen"`
	CreatedAt   time.Time              `json:"created_at"`
	UpdatedAt   time.Time              `json:"updated_at"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// PublicUser represents public user information
type PublicUser struct {
	ID          string    `json:"id"`
	Username    *string   `json:"username,omitempty"`
	DisplayName *string   `json:"display_name,omitempty"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	Role        string    `json:"role"`
	IsOnline    bool      `json:"is_online"`
	LastSeen    time.Time `json:"last_seen"`
}

// Contact represents a user's contact
type Contact struct {
	ID        string    `json:"id"`
	ContactID string    `json:"contact_id"`
	Nickname  *string   `json:"nickname,omitempty"`
	Blocked   bool      `json:"blocked"`
	CreatedAt time.Time `json:"created_at"`

	// User info
	Username    *string   `json:"username,omitempty"`
	DisplayName *string   `json:"display_name,omitempty"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	Status      string    `json:"status"`
	IsOnline    bool      `json:"is_online"`
	LastSeen    time.Time `json:"last_seen"`
}

// ModelProfile represents a model's public profile
type ModelProfile struct {
	ID          string    `json:"id"`
	Username    *string   `json:"username,omitempty"`
	DisplayName *string   `json:"display_name,omitempty"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	Status      string    `json:"status"`
	IsOnline    bool      `json:"is_online"`
	LastSeen    time.Time `json:"last_seen"`
	CreatedAt   time.Time `json:"created_at"`

	// Gallery info
	GalleryID  *string `json:"gallery_id,omitempty"`
	MediaCount *int    `json:"media_count,omitempty"`
}

// UpdateProfileRequest represents a profile update request
type UpdateProfileRequest struct {
	Username    *string                `json:"username,omitempty" validate:"omitempty,min=3,max=30,alphanum"`
	DisplayName *string                `json:"display_name,omitempty" validate:"omitempty,max=100"`
	AvatarURL   *string                `json:"avatar_url,omitempty" validate:"omitempty,url"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// AddContactRequest represents a request to add a contact
type AddContactRequest struct {
	ContactID string  `json:"contact_id" validate:"required,uuid"`
	Nickname  *string `json:"nickname,omitempty" validate:"omitempty,max=100"`
}

// UpdateContactRequest represents a contact update request
type UpdateContactRequest struct {
	Nickname *string `json:"nickname,omitempty" validate:"omitempty,max=100"`
	Blocked  *bool   `json:"blocked,omitempty"`
}

// ContactsResponse represents a list of contacts
type ContactsResponse struct {
	Contacts []*Contact `json:"contacts"`
	Total    int        `json:"total"`
}

// ModelFilters for querying models
type ModelFilters struct {
	Search     string `query:"search"`
	OnlineOnly bool   `query:"online_only"`
	SortBy     string `query:"sort_by"` // newest, active, popular
	Page       int    `query:"page"`
	PageSize   int    `query:"page_size"`
}

// ModelsResponse represents a paginated list of models
type ModelsResponse struct {
	Models     []*ModelProfile `json:"models"`
	TotalCount int             `json:"total_count"`
	Page       int             `json:"page"`
	PageSize   int             `json:"page_size"`
	HasMore    bool            `json:"has_more"`
}

// Device represents a user's device
type Device struct {
	ID         string    `json:"id"`
	DeviceID   string    `json:"device_id"`
	Name       *string   `json:"name,omitempty"`
	Platform   string    `json:"platform"` // web, ios, android
	PublicKey  string    `json:"public_key"`
	LastActive time.Time `json:"last_active"`
	CreatedAt  time.Time `json:"created_at"`
}

// UserProfileResponse represents the complete user profile
type UserProfileResponse struct {
	User     *User        `json:"user"`
	Devices  []*Device    `json:"devices,omitempty"`
	Settings UserSettings `json:"settings"`
}

// UserSettings represents user preferences
type UserSettings struct {
	NotificationsEnabled bool                   `json:"notifications_enabled"`
	Language             string                 `json:"language"`
	Theme                string                 `json:"theme"`
	Privacy              PrivacySettings        `json:"privacy"`
	Metadata             map[string]interface{} `json:"metadata,omitempty"`
}

// PrivacySettings represents privacy preferences
type PrivacySettings struct {
	ShowOnline      bool `json:"show_online"`
	ShowLastSeen    bool `json:"show_last_seen"`
	AllowDiscovery  bool `json:"allow_discovery"`
	RequireApproval bool `json:"require_approval"`
}

// Constants for user roles and status
const (
	RoleUser  = "user"
	RoleModel = "model"
	RoleAdmin = "admin"

	StatusActive    = "active"
	StatusInactive  = "inactive"
	StatusSuspended = "suspended"
	StatusDeleted   = "deleted"
)
