package users

import (
	"context"
	"database/sql"
	"strings"

	"chat-e2ee/internal/media"

	"github.com/gofiber/fiber/v2"
	"github.com/minio/minio-go/v7"
)

// Handler handles user-related HTTP requests
type Handler struct {
	service      *Service
	mediaService *media.Service
}

// NewHandler creates a new user handler
func NewHandler(db *sql.DB, minioClient *minio.Client, bucketMedia string) *Handler {
	return &Handler{
		service:      NewService(db),
		mediaService: media.NewService(db, minioClient, bucketMedia, "", ""),
	}
}

// GetMe returns the authenticated user's profile
func (h *Handler) GetMe(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Get user info
	user, err := h.service.GetUser(c.Context(), userID)
	if err != nil {
		if err == ErrUserNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "User not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch user",
		})
	}

	// Get user devices
	devices, err := h.getUserDevices(c.Context(), userID)
	if err != nil {
		// Log error but don't fail the request
		devices = []*Device{}
	}

	// TODO: Get user settings from a settings table or user metadata
	settings := UserSettings{
		NotificationsEnabled: true,
		Language:             "en",
		Theme:                "light",
		Privacy: PrivacySettings{
			ShowOnline:      true,
			ShowLastSeen:    true,
			AllowDiscovery:  true,
			RequireApproval: false,
		},
	}

	return c.JSON(UserProfileResponse{
		User:     user,
		Devices:  devices,
		Settings: settings,
	})
}

// UpdateMe updates the authenticated user's profile
func (h *Handler) UpdateMe(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Parse request
	var req UpdateProfileRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Validate request
	if req.Username != nil {
		// Trim spaces and convert to lowercase
		username := strings.TrimSpace(strings.ToLower(*req.Username))
		req.Username = &username
	}

	// Update profile
	user, err := h.service.UpdateProfile(c.Context(), userID, &req)
	if err != nil {
		switch err {
		case ErrUsernameExists:
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"error": "Username already taken",
			})
		case ErrInvalidUsername:
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Invalid username format. Use 3-30 alphanumeric characters or underscore",
			})
		default:
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to update profile",
			})
		}
	}

	return c.JSON(fiber.Map{
		"message": "Profile updated successfully",
		"user":    user,
	})
}

// UpdateAvatar handles avatar upload
func (h *Handler) UpdateAvatar(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Get file from form
	file, err := c.FormFile("avatar")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "No file provided",
		})
	}

	// Validate file size (max 5MB for avatars)
	if file.Size > 5*1024*1024 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "File too large. Maximum size is 5MB",
		})
	}

	// Validate file type
	if err := media.ValidateFileType(file.Filename, file.Header.Get("Content-Type")); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid file type. Only images are allowed",
		})
	}

	// Open file
	src, err := file.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to open file",
		})
	}
	defer src.Close()

	// Upload file
	mediaFile, err := h.mediaService.UploadFile(c.Context(), src, file, userID, "photo")
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to upload avatar",
		})
	}

	// Update user avatar URL
	err = h.service.UpdateAvatar(c.Context(), userID, mediaFile.URL)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update avatar",
		})
	}

	return c.JSON(fiber.Map{
		"message":    "Avatar updated successfully",
		"avatar_url": mediaFile.URL,
	})
}

// GetUser returns a public user profile
func (h *Handler) GetUser(c *fiber.Ctx) error {
	targetUserID := c.Params("id")

	// Get user info
	user, err := h.service.GetUser(c.Context(), targetUserID)
	if err != nil {
		if err == ErrUserNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "User not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch user",
		})
	}

	// Return public info only
	publicUser := &PublicUser{
		ID:          user.ID,
		Username:    user.Username,
		DisplayName: user.DisplayName,
		AvatarURL:   user.AvatarURL,
		Role:        user.Role,
		IsOnline:    user.IsOnline,
		LastSeen:    user.LastSeen,
	}

	return c.JSON(publicUser)
}

// GetContacts returns the user's contact list
func (h *Handler) GetContacts(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)
	includeBlocked := c.QueryBool("include_blocked", false)

	contacts, err := h.service.GetContacts(c.Context(), userID, includeBlocked)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch contacts",
		})
	}

	return c.JSON(ContactsResponse{
		Contacts: contacts,
		Total:    len(contacts),
	})
}

// AddContact adds a new contact
func (h *Handler) AddContact(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)

	// Parse request
	var req AddContactRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Add contact
	contact, err := h.service.AddContact(c.Context(), userID, &req)
	if err != nil {
		switch err {
		case ErrUserNotFound:
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "User not found",
			})
		case ErrSelfContact:
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Cannot add yourself as a contact",
			})
		case ErrContactExists:
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"error": "Contact already exists",
			})
		default:
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to add contact",
			})
		}
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message": "Contact added successfully",
		"contact": contact,
	})
}

// UpdateContact updates contact information
func (h *Handler) UpdateContact(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)
	contactID := c.Params("id")

	// Parse request
	var req UpdateContactRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Update contact
	err := h.service.UpdateContact(c.Context(), userID, contactID, &req)
	if err != nil {
		if err == ErrContactNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Contact not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update contact",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Contact updated successfully",
	})
}

// RemoveContact removes a contact
func (h *Handler) RemoveContact(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)
	contactID := c.Params("id")

	err := h.service.RemoveContact(c.Context(), userID, contactID)
	if err != nil {
		if err == ErrContactNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Contact not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to remove contact",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Contact removed successfully",
	})
}

// BlockContact blocks a contact
func (h *Handler) BlockContact(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)
	contactID := c.Params("id")

	err := h.service.BlockContact(c.Context(), userID, contactID, true)
	if err != nil {
		if err == ErrContactNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Contact not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to block contact",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Contact blocked successfully",
	})
}

// UnblockContact unblocks a contact
func (h *Handler) UnblockContact(c *fiber.Ctx) error {
	userID := c.Locals("userID").(string)
	contactID := c.Params("id")

	err := h.service.BlockContact(c.Context(), userID, contactID, false)
	if err != nil {
		if err == ErrContactNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Contact not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to unblock contact",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Contact unblocked successfully",
	})
}

// Helper function to get user devices
func (h *Handler) getUserDevices(ctx context.Context, userID string) ([]*Device, error) {
	query := `
		SELECT id, device_id, name, platform, public_key, last_active, created_at
		FROM user_devices
		WHERE user_id = $1
		ORDER BY last_active DESC`

	rows, err := h.service.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	devices := make([]*Device, 0)
	for rows.Next() {
		var d Device
		var name sql.NullString

		err := rows.Scan(&d.ID, &d.DeviceID, &name, &d.Platform,
			&d.PublicKey, &d.LastActive, &d.CreatedAt)
		if err != nil {
			continue
		}

		// Handle nullable fields
		if name.Valid {
			d.Name = &name.String
		}

		devices = append(devices, &d)
	}

	return devices, nil
}
