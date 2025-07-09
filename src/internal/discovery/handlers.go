package discovery

import (
	"context"
	"database/sql"
	"strings"

	"chat-e2ee/internal/users"

	"github.com/gofiber/fiber/v2"
)

// Handler handles model discovery endpoints
type Handler struct {
	userService *users.Service
	db          *sql.DB
}

// NewHandler creates a new discovery handler
func NewHandler(db *sql.DB) *Handler {
	return &Handler{
		userService: users.NewService(db),
		db:          db,
	}
}

// GetModels returns a list of models for discovery
func (h *Handler) GetModels(c *fiber.Ctx) error {
	// Parse filters
	filters := &users.ModelFilters{
		Search:     strings.TrimSpace(c.Query("search")),
		OnlineOnly: c.QueryBool("online_only", false),
		SortBy:     c.Query("sort_by", "active"), // default sort by activity
		Page:       c.QueryInt("page", 1),
		PageSize:   c.QueryInt("page_size", 20),
	}

	// Validate pagination
	if filters.Page < 1 {
		filters.Page = 1
	}
	if filters.PageSize < 1 || filters.PageSize > 100 {
		filters.PageSize = 20
	}

	// Validate sort options
	validSorts := map[string]bool{
		"newest":  true,
		"active":  true,
		"popular": true,
	}
	if !validSorts[filters.SortBy] {
		filters.SortBy = "active"
	}

	// Get models
	models, totalCount, err := h.userService.GetModels(c.Context(), filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch models",
		})
	}

	// Build response
	return c.JSON(users.ModelsResponse{
		Models:     models,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		HasMore:    totalCount > filters.Page*filters.PageSize,
	})
}

// SearchModels performs a search for models
func (h *Handler) SearchModels(c *fiber.Ctx) error {
	query := strings.TrimSpace(c.Query("q"))
	if query == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Search query is required",
		})
	}

	// Use the same filters as GetModels but with search
	filters := &users.ModelFilters{
		Search:     query,
		OnlineOnly: c.QueryBool("online_only", false),
		SortBy:     "active",
		Page:       1,
		PageSize:   20,
	}

	// Get models
	models, totalCount, err := h.userService.GetModels(c.Context(), filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to search models",
		})
	}

	return c.JSON(fiber.Map{
		"query":   query,
		"results": models,
		"total":   totalCount,
	})
}

// GetModelProfile returns detailed model profile
func (h *Handler) GetModelProfile(c *fiber.Ctx) error {
	modelID := c.Params("id")

	// Get user info
	user, err := h.userService.GetUser(c.Context(), modelID)
	if err != nil {
		if err == users.ErrUserNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Model not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch model",
		})
	}

	// Verify it's a model
	if user.Role != users.RoleModel {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Model not found",
		})
	}

	// Get gallery info
	var galleryInfo *ModelGalleryInfo
	galleryInfo, _ = h.getModelGalleryInfo(c.Context(), modelID)

	// Build profile response
	profile := &ModelProfileResponse{
		ID:          user.ID,
		Username:    user.Username,
		DisplayName: user.DisplayName,
		AvatarURL:   user.AvatarURL,
		Status:      user.Status,
		IsOnline:    user.IsOnline,
		LastSeen:    user.LastSeen,
		CreatedAt:   user.CreatedAt,
		Gallery:     galleryInfo,
		Metadata:    h.getPublicMetadata(user.Metadata),
	}

	return c.JSON(profile)
}

// GetPopularModels returns popular/featured models
func (h *Handler) GetPopularModels(c *fiber.Ctx) error {
	// Use filters optimized for popularity
	filters := &users.ModelFilters{
		SortBy:   "popular",
		Page:     1,
		PageSize: c.QueryInt("limit", 12),
	}

	if filters.PageSize > 50 {
		filters.PageSize = 50
	}

	// Get models
	models, _, err := h.userService.GetModels(c.Context(), filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch popular models",
		})
	}

	return c.JSON(fiber.Map{
		"models": models,
		"type":   "popular",
	})
}

// GetNewModels returns recently joined models
func (h *Handler) GetNewModels(c *fiber.Ctx) error {
	// Use filters optimized for new models
	filters := &users.ModelFilters{
		SortBy:   "newest",
		Page:     1,
		PageSize: c.QueryInt("limit", 12),
	}

	if filters.PageSize > 50 {
		filters.PageSize = 50
	}

	// Get models
	models, _, err := h.userService.GetModels(c.Context(), filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch new models",
		})
	}

	return c.JSON(fiber.Map{
		"models": models,
		"type":   "new",
	})
}

// GetOnlineModels returns currently online models
func (h *Handler) GetOnlineModels(c *fiber.Ctx) error {
	// Use filters for online models
	filters := &users.ModelFilters{
		OnlineOnly: true,
		SortBy:     "active",
		Page:       c.QueryInt("page", 1),
		PageSize:   c.QueryInt("page_size", 20),
	}

	if filters.PageSize > 100 {
		filters.PageSize = 100
	}

	// Get models
	models, totalCount, err := h.userService.GetModels(c.Context(), filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch online models",
		})
	}

	return c.JSON(fiber.Map{
		"models":       models,
		"total_online": totalCount,
		"page":         filters.Page,
		"has_more":     totalCount > filters.Page*filters.PageSize,
	})
}

// Helper functions

func (h *Handler) getModelGalleryInfo(ctx context.Context, modelID string) (*ModelGalleryInfo, error) {
	var info ModelGalleryInfo

	query := `
		SELECT g.id, g.media_count, g.total_size_bytes, g.updated_at,
		       (SELECT url FROM gallery_media 
		        WHERE gallery_id = g.id AND is_public = true 
		        ORDER BY created_at DESC LIMIT 1) as preview_url
		FROM model_galleries g
		WHERE g.model_id = $1`

	err := h.db.QueryRowContext(ctx, query, modelID).Scan(
		&info.GalleryID, &info.MediaCount, &info.TotalSize,
		&info.UpdatedAt, &info.PreviewURL,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	// Get sample media
	mediaQuery := `
		SELECT url, thumbnail_url, type
		FROM gallery_media
		WHERE gallery_id = $1 AND is_public = true
		ORDER BY created_at DESC
		LIMIT 6`

	rows, err := h.db.QueryContext(ctx, mediaQuery, info.GalleryID)
	if err == nil {
		defer rows.Close()
		info.SampleMedia = make([]*SampleMedia, 0, 6)

		for rows.Next() {
			var m SampleMedia
			if err := rows.Scan(&m.URL, &m.ThumbnailURL, &m.Type); err == nil {
				info.SampleMedia = append(info.SampleMedia, &m)
			}
		}
	}

	return &info, nil
}

func (h *Handler) getPublicMetadata(metadata map[string]interface{}) map[string]interface{} {
	if metadata == nil {
		return nil
	}

	// Filter out private fields
	public := make(map[string]interface{})
	publicFields := map[string]bool{
		"bio":       true,
		"location":  true,
		"languages": true,
		"interests": true,
		"website":   true,
		"social":    true,
	}

	for key, value := range metadata {
		if publicFields[key] {
			public[key] = value
		}
	}

	return public
}
