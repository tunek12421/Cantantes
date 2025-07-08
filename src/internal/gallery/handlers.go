package gallery

import (
	"database/sql"
	"errors"

	"github.com/gofiber/fiber/v2"
)

var (
	ErrGalleryNotFound = errors.New("gallery not found")
	ErrUnauthorized    = errors.New("unauthorized access")
)

// Handler handles gallery-related HTTP requests
type Handler struct {
	service *Service
}

// NewHandler creates a new gallery handler
func NewHandler(db *sql.DB) *Handler {
	return &Handler{
		service: NewService(db),
	}
}

// GetMyGallery returns the authenticated user's gallery
func (h *Handler) GetMyGallery(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Get or create gallery
	gallery, err := h.service.GetGallery(c.Context(), userID)
	if err != nil {
		if err == ErrGalleryNotFound {
			// Create gallery if it doesn't exist
			gallery, err = h.service.CreateGallery(c.Context(), userID)
			if err != nil {
				return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
					"error": "Failed to create gallery",
				})
			}
		} else {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to fetch gallery",
			})
		}
	}

	// Parse filters
	filters := &MediaFilters{
		Type:     c.Query("type"),
		Page:     c.QueryInt("page", 1),
		PageSize: c.QueryInt("page_size", 20),
	}

	if c.Query("is_public") != "" {
		isPublic := c.QueryBool("is_public")
		filters.IsPublic = &isPublic
	}

	// Get media items
	items, totalCount, err := h.service.GetGalleryMedia(c.Context(), gallery.ID, filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch gallery media",
		})
	}

	// Return response
	return c.JSON(fiber.Map{
		"gallery": gallery,
		"media": fiber.Map{
			"items":       items,
			"total_count": totalCount,
			"page":        filters.Page,
			"page_size":   filters.PageSize,
			"has_more":    totalCount > filters.Page*filters.PageSize,
		},
	})
}

// GetUserGallery returns a specific user's public gallery
func (h *Handler) GetUserGallery(c *fiber.Ctx) error {
	userID := c.Params("userId")

	// Get gallery
	gallery, err := h.service.GetGallery(c.Context(), userID)
	if err != nil {
		if err == ErrGalleryNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Gallery not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch gallery",
		})
	}

	// Parse filters - only show public items for other users
	filters := &MediaFilters{
		Type:     c.Query("type"),
		Page:     c.QueryInt("page", 1),
		PageSize: c.QueryInt("page_size", 20),
	}

	// Force public only for non-owner
	requestingUserID := c.Locals("userID")
	if requestingUserID != userID {
		isPublic := true
		filters.IsPublic = &isPublic
	}

	// Get media items
	items, totalCount, err := h.service.GetGalleryMedia(c.Context(), gallery.ID, filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch gallery media",
		})
	}

	// Return response
	return c.JSON(fiber.Map{
		"gallery": gallery,
		"media": fiber.Map{
			"items":       items,
			"total_count": totalCount,
			"page":        filters.Page,
			"page_size":   filters.PageSize,
			"has_more":    totalCount > filters.Page*filters.PageSize,
		},
	})
}

// UpdateGallerySettings updates gallery settings
func (h *Handler) UpdateGallerySettings(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Parse request
	var settings map[string]interface{}
	if err := c.BodyParser(&settings); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Get user's gallery
	gallery, err := h.service.GetGallery(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Gallery not found",
		})
	}

	// Update settings
	err = h.service.UpdateGallerySettings(c.Context(), gallery.ID, settings)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update settings",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Settings updated successfully",
	})
}

// DiscoverGalleries returns galleries for discovery/browsing
func (h *Handler) DiscoverGalleries(c *fiber.Ctx) error {
	page := c.QueryInt("page", 1)
	pageSize := c.QueryInt("page_size", 20)

	if pageSize > 100 {
		pageSize = 100
	}

	offset := (page - 1) * pageSize

	// Get galleries
	galleries, err := h.service.GetModelGalleries(c.Context(), pageSize, offset)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch galleries",
		})
	}

	return c.JSON(fiber.Map{
		"galleries": galleries,
		"page":      page,
		"page_size": pageSize,
		"has_more":  len(galleries) == pageSize,
	})
}

// GetGalleryStats returns statistics for a gallery
func (h *Handler) GetGalleryStats(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Get gallery
	gallery, err := h.service.GetGallery(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Gallery not found",
		})
	}

	// Get stats by type
	var stats []struct {
		Type  string `json:"type"`
		Count int    `json:"count"`
		Size  int64  `json:"total_size"`
	}

	query := `
		SELECT type, COUNT(*) as count, SUM(size_bytes) as total_size
		FROM gallery_media
		WHERE gallery_id = $1
		GROUP BY type`

	rows, err := h.service.db.QueryContext(c.Context(), query, gallery.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch stats",
		})
	}
	defer rows.Close()

	for rows.Next() {
		var stat struct {
			Type  string `json:"type"`
			Count int    `json:"count"`
			Size  int64  `json:"total_size"`
		}
		rows.Scan(&stat.Type, &stat.Count, &stat.Size)
		stats = append(stats, stat)
	}

	return c.JSON(fiber.Map{
		"gallery_id":    gallery.ID,
		"total_size":    gallery.TotalSize,
		"media_count":   gallery.MediaCount,
		"stats_by_type": stats,
		"updated_at":    gallery.UpdatedAt,
	})
}
