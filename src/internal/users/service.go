package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"

	"github.com/google/uuid"
	"github.com/lib/pq"
)

// Common errors
var (
	ErrUserNotFound    = errors.New("user not found")
	ErrUsernameExists  = errors.New("username already exists")
	ErrInvalidUsername = errors.New("invalid username format")
	ErrContactNotFound = errors.New("contact not found")
	ErrSelfContact     = errors.New("cannot add yourself as contact")
	ErrContactExists   = errors.New("contact already exists")
	ErrInvalidRole     = errors.New("invalid user role")
	ErrUnauthorized    = errors.New("unauthorized")
)

// Service handles user-related operations
type Service struct {
	db *sql.DB
}

// NewService creates a new user service
func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

// GetUser retrieves a user by ID
func (s *Service) GetUser(ctx context.Context, userID string) (*User, error) {
	log.Printf("[GetUser] Starting - Looking for user ID: %s", userID)

	var user User
	var username, displayName, avatarURL sql.NullString
	var metadata sql.NullString

	query := `
        SELECT id, phone_number, username, display_name, avatar_url, 
               role, status, is_online, last_seen, created_at, 
               updated_at, metadata
        FROM users 
        WHERE id = $1 AND deleted_at IS NULL`

	log.Printf("[GetUser] Executing query for user: %s", userID)

	err := s.db.QueryRowContext(ctx, query, userID).Scan(
		&user.ID, &user.PhoneNumber, &username, &displayName,
		&avatarURL, &user.Role, &user.Status, &user.IsOnline,
		&user.LastSeen, &user.CreatedAt, &user.UpdatedAt, &metadata,
	)

	if err != nil {
		log.Printf("[GetUser] Database error for user %s: %v", userID, err)
		if err == sql.ErrNoRows {
			log.Printf("[GetUser] User not found: %s", userID)
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	log.Printf("[GetUser] User found: %s, role: %s, status: %s", user.ID, user.Role, user.Status)

	// Handle nullable fields
	if username.Valid {
		user.Username = &username.String
	}
	if displayName.Valid {
		user.DisplayName = &displayName.String
	}
	if avatarURL.Valid {
		user.AvatarURL = &avatarURL.String
	}

	// Parse metadata if exists
	if metadata.Valid && metadata.String != "" {
		if err := json.Unmarshal([]byte(metadata.String), &user.Metadata); err != nil {
			log.Printf("[GetUser] Error parsing metadata: %v", err)
		}
	}

	log.Printf("[GetUser] Successfully retrieved user: %s", userID)
	return &user, nil
}

// GetUserByUsername retrieves a user by username
func (s *Service) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	var user User
	var metadata sql.NullString

	query := `
		SELECT id, phone_number, username, display_name, avatar_url, 
		       role, status, is_online, last_seen, created_at, 
		       updated_at, metadata
		FROM users 
		WHERE username = $1 AND deleted_at IS NULL`

	err := s.db.QueryRowContext(ctx, query, username).Scan(
		&user.ID, &user.PhoneNumber, &user.Username, &user.DisplayName,
		&user.AvatarURL, &user.Role, &user.Status, &user.IsOnline,
		&user.LastSeen, &user.CreatedAt, &user.UpdatedAt, &metadata,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	// Parse metadata if exists
	if metadata.Valid && metadata.String != "" {
		json.Unmarshal([]byte(metadata.String), &user.Metadata)
	}

	return &user, nil
}

// UpdateProfile updates user profile information
func (s *Service) UpdateProfile(ctx context.Context, userID string, update *UpdateProfileRequest) (*User, error) {
	// Start transaction
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Build dynamic update query
	query := `UPDATE users SET updated_at = NOW()`
	args := []interface{}{}
	argCount := 1

	if update.Username != nil {
		// Validate username format (alphanumeric, underscore, 3-30 chars)
		if !isValidUsername(*update.Username) {
			return nil, ErrInvalidUsername
		}

		// Check if username is available
		var exists bool
		err = tx.QueryRowContext(ctx,
			"SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND id != $2)",
			*update.Username, userID,
		).Scan(&exists)
		if err != nil {
			return nil, err
		}
		if exists {
			return nil, ErrUsernameExists
		}

		query += fmt.Sprintf(", username = $%d", argCount)
		args = append(args, *update.Username)
		argCount++
	}

	if update.DisplayName != nil {
		query += fmt.Sprintf(", display_name = $%d", argCount)
		args = append(args, *update.DisplayName)
		argCount++
	}

	if update.AvatarURL != nil {
		query += fmt.Sprintf(", avatar_url = $%d", argCount)
		args = append(args, *update.AvatarURL)
		argCount++
	}

	if update.Metadata != nil {
		metadataJSON, err := json.Marshal(update.Metadata)
		if err != nil {
			return nil, err
		}
		query += fmt.Sprintf(", metadata = $%d", argCount)
		args = append(args, string(metadataJSON))
		argCount++
	}

	// Add WHERE clause
	query += fmt.Sprintf(" WHERE id = $%d", argCount)
	args = append(args, userID)

	// Execute update
	_, err = tx.ExecContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}

	// Commit transaction
	if err = tx.Commit(); err != nil {
		return nil, err
	}

	// Return updated user
	return s.GetUser(ctx, userID)
}

// UpdateAvatar updates user's avatar URL
func (s *Service) UpdateAvatar(ctx context.Context, userID, avatarURL string) error {
	query := `
		UPDATE users 
		SET avatar_url = $1, updated_at = NOW() 
		WHERE id = $2`

	_, err := s.db.ExecContext(ctx, query, avatarURL, userID)
	return err
}

// GetContacts retrieves user's contacts
func (s *Service) GetContacts(ctx context.Context, userID string, includeBlocked bool) ([]*Contact, error) {
	query := `
		SELECT c.id, c.contact_id, c.nickname, c.blocked, c.created_at,
		       u.username, u.display_name, u.avatar_url, u.status, u.is_online, u.last_seen
		FROM user_contacts c
		JOIN users u ON u.id = c.contact_id
		WHERE c.user_id = $1
		  AND u.deleted_at IS NULL`

	if !includeBlocked {
		query += " AND c.blocked = false"
	}

	query += " ORDER BY u.display_name, u.username"

	rows, err := s.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	contacts := make([]*Contact, 0)
	for rows.Next() {
		var c Contact
		err := rows.Scan(
			&c.ID, &c.ContactID, &c.Nickname, &c.Blocked, &c.CreatedAt,
			&c.Username, &c.DisplayName, &c.AvatarURL, &c.Status,
			&c.IsOnline, &c.LastSeen,
		)
		if err != nil {
			continue
		}
		contacts = append(contacts, &c)
	}

	return contacts, nil
}

// AddContact adds a new contact
func (s *Service) AddContact(ctx context.Context, userID string, req *AddContactRequest) (*Contact, error) {
	// Validate not adding self
	if req.ContactID == userID {
		return nil, ErrSelfContact
	}

	// Check if contact user exists
	var exists bool
	err := s.db.QueryRowContext(ctx,
		"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)",
		req.ContactID,
	).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, ErrUserNotFound
	}

	// Check if already a contact
	err = s.db.QueryRowContext(ctx,
		"SELECT EXISTS(SELECT 1 FROM user_contacts WHERE user_id = $1 AND contact_id = $2)",
		userID, req.ContactID,
	).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, ErrContactExists
	}

	// Insert contact
	contactID := uuid.New().String()
	query := `
		INSERT INTO user_contacts (id, user_id, contact_id, nickname, created_at)
		VALUES ($1, $2, $3, $4, NOW())`

	_, err = s.db.ExecContext(ctx, query, contactID, userID, req.ContactID, req.Nickname)
	if err != nil {
		return nil, err
	}

	// Return contact info
	return s.GetContact(ctx, userID, req.ContactID)
}

// GetContact retrieves a specific contact
func (s *Service) GetContact(ctx context.Context, userID, contactID string) (*Contact, error) {
	var c Contact

	query := `
		SELECT c.id, c.contact_id, c.nickname, c.blocked, c.created_at,
		       u.username, u.display_name, u.avatar_url, u.status, u.is_online, u.last_seen
		FROM user_contacts c
		JOIN users u ON u.id = c.contact_id
		WHERE c.user_id = $1 AND c.contact_id = $2
		  AND u.deleted_at IS NULL`

	err := s.db.QueryRowContext(ctx, query, userID, contactID).Scan(
		&c.ID, &c.ContactID, &c.Nickname, &c.Blocked, &c.CreatedAt,
		&c.Username, &c.DisplayName, &c.AvatarURL, &c.Status,
		&c.IsOnline, &c.LastSeen,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrContactNotFound
		}
		return nil, err
	}

	return &c, nil
}

// UpdateContact updates contact information
func (s *Service) UpdateContact(ctx context.Context, userID, contactID string, update *UpdateContactRequest) error {
	query := `UPDATE user_contacts SET`
	args := []interface{}{}
	argCount := 1
	updates := []string{}

	if update.Nickname != nil {
		updates = append(updates, fmt.Sprintf("nickname = $%d", argCount))
		args = append(args, *update.Nickname)
		argCount++
	}

	if update.Blocked != nil {
		updates = append(updates, fmt.Sprintf("blocked = $%d", argCount))
		args = append(args, *update.Blocked)
		argCount++
	}

	if len(updates) == 0 {
		return nil // Nothing to update
	}

	query += " " + joinStrings(updates, ", ")
	query += fmt.Sprintf(" WHERE user_id = $%d AND contact_id = $%d", argCount, argCount+1)
	args = append(args, userID, contactID)

	result, err := s.db.ExecContext(ctx, query, args...)
	if err != nil {
		return err
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return ErrContactNotFound
	}

	return nil
}

// RemoveContact removes a contact
func (s *Service) RemoveContact(ctx context.Context, userID, contactID string) error {
	result, err := s.db.ExecContext(ctx,
		"DELETE FROM user_contacts WHERE user_id = $1 AND contact_id = $2",
		userID, contactID,
	)
	if err != nil {
		return err
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return ErrContactNotFound
	}

	return nil
}

// BlockContact blocks/unblocks a contact
func (s *Service) BlockContact(ctx context.Context, userID, contactID string, blocked bool) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE user_contacts SET blocked = $1 WHERE user_id = $2 AND contact_id = $3",
		blocked, userID, contactID,
	)
	if err != nil {
		return err
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return ErrContactNotFound
	}

	return nil
}

// GetModels retrieves models for discovery
func (s *Service) GetModels(ctx context.Context, filters *ModelFilters) ([]*ModelProfile, int, error) {
	// Build query
	query := `
		SELECT u.id, u.username, u.display_name, u.avatar_url, u.status, 
		       u.is_online, u.last_seen, u.created_at,
		       g.id as gallery_id, g.media_count, g.updated_at as gallery_updated
		FROM users u
		LEFT JOIN model_galleries g ON g.model_id = u.id
		WHERE u.role = 'model' 
		  AND u.status = 'active' 
		  AND u.deleted_at IS NULL`

	countQuery := `
		SELECT COUNT(DISTINCT u.id) 
		FROM users u
		WHERE u.role = 'model' 
		  AND u.status = 'active' 
		  AND u.deleted_at IS NULL`

	args := []interface{}{}
	argCount := 1

	// Apply filters
	if filters.Search != "" {
		searchCondition := fmt.Sprintf(" AND (u.username ILIKE $%d OR u.display_name ILIKE $%d)", argCount, argCount)
		query += searchCondition
		countQuery += searchCondition
		searchParam := "%" + filters.Search + "%"
		args = append(args, searchParam)
		argCount++
	}

	if filters.OnlineOnly {
		query += " AND u.is_online = true"
		countQuery += " AND u.is_online = true"
	}

	// Get total count
	var totalCount int
	err := s.db.QueryRowContext(ctx, countQuery, args...).Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	// Add ordering and pagination
	switch filters.SortBy {
	case "newest":
		query += " ORDER BY u.created_at DESC"
	case "active":
		query += " ORDER BY u.last_seen DESC"
	case "popular":
		query += " ORDER BY g.media_count DESC NULLS LAST"
	default:
		query += " ORDER BY u.display_name, u.username"
	}

	// Pagination
	offset := (filters.Page - 1) * filters.PageSize
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argCount, argCount+1)
	args = append(args, filters.PageSize, offset)

	// Execute query
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	models := make([]*ModelProfile, 0)
	for rows.Next() {
		var m ModelProfile
		var galleryID sql.NullString
		var mediaCount sql.NullInt64
		var galleryUpdated pq.NullTime

		err := rows.Scan(
			&m.ID, &m.Username, &m.DisplayName, &m.AvatarURL,
			&m.Status, &m.IsOnline, &m.LastSeen, &m.CreatedAt,
			&galleryID, &mediaCount, &galleryUpdated,
		)
		if err != nil {
			continue
		}

		// Set gallery info if exists
		if galleryID.Valid {
			m.GalleryID = &galleryID.String
			if mediaCount.Valid {
				mc := int(mediaCount.Int64)
				m.MediaCount = &mc
			}
		}

		models = append(models, &m)
	}

	return models, totalCount, nil
}

// Helper functions

func isValidUsername(username string) bool {
	// Username rules: 3-30 chars, alphanumeric + underscore
	if len(username) < 3 || len(username) > 30 {
		return false
	}

	for _, char := range username {
		if !((char >= 'a' && char <= 'z') ||
			(char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') ||
			char == '_') {
			return false
		}
	}

	return true
}

func joinStrings(strs []string, sep string) string {
	result := ""
	for i, s := range strs {
		if i > 0 {
			result += sep
		}
		result += s
	}
	return result
}
