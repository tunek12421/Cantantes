#!/bin/bash

# Script to create Phase 3 WebSocket files for Chat E2EE

echo "Creating Phase 3 WebSocket files..."

# Create directories
mkdir -p src/internal/relay
mkdir -p src/internal/presence

# Create message.go
cat > src/internal/relay/message.go << 'ENDOFFILE'
package relay

import (
	"encoding/json"
	"time"
)

// MessageType defines the type of WebSocket message
type MessageType string

const (
	// Client to Server
	MessageTypeText     MessageType = "message"
	MessageTypeTyping   MessageType = "typing"
	MessageTypeRead     MessageType = "read"
	MessageTypePresence MessageType = "presence"

	// Server to Client
	MessageTypeDelivery MessageType = "delivery"
	MessageTypeError    MessageType = "error"
	MessageTypeStatus   MessageType = "status"

	// System
	MessageTypeHeartbeat MessageType = "heartbeat"
	MessageTypePing      MessageType = "ping"
	MessageTypePong      MessageType = "pong"
)

// Message represents a WebSocket message for E2EE relay
type Message struct {
	// Message identification
	ID        string      `json:"id"`
	Type      MessageType `json:"type"`
	Timestamp time.Time   `json:"timestamp"`

	// Routing information
	From     string `json:"from,omitempty"`     // UserID of sender
	To       string `json:"to,omitempty"`       // UserID of recipient
	DeviceID string `json:"device_id,omitempty"` // Device that sent the message

	// E2EE payload - server never decrypts this
	Payload string `json:"payload,omitempty"` // Base64 encoded encrypted data

	// Metadata (not encrypted)
	Metadata map[string]interface{} `json:"metadata,omitempty"`
}

// ClientMessage is what clients send
type ClientMessage struct {
	Type    MessageType `json:"type"`
	To      string      `json:"to"`      // Target user ID
	Payload string      `json:"payload"` // Encrypted content
}

// ServerMessage is what server sends to clients
type ServerMessage struct {
	Type      MessageType `json:"type"`
	From      string      `json:"from,omitempty"`
	Payload   string      `json:"payload,omitempty"`
	Timestamp time.Time   `json:"timestamp"`
	MessageID string      `json:"message_id,omitempty"`
}

// TypingIndicator for typing status
type TypingIndicator struct {
	UserID   string `json:"user_id"`
	IsTyping bool   `json:"is_typing"`
}

// ReadReceipt for read confirmations
type ReadReceipt struct {
	MessageID string    `json:"message_id"`
	ReadAt    time.Time `json:"read_at"`
}

// PresenceUpdate for online/offline status
type PresenceUpdate struct {
	UserID   string    `json:"user_id"`
	Status   string    `json:"status"` // "online", "offline", "away"
	LastSeen time.Time `json:"last_seen"`
}

// ErrorMessage for error responses
type ErrorMessage struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ParseMessage parses raw WebSocket message
func ParseMessage(data []byte) (*ClientMessage, error) {
	var msg ClientMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, err
	}
	return &msg, nil
}

// NewServerMessage creates a server message
func NewServerMessage(msgType MessageType, from string, payload string) *ServerMessage {
	return &ServerMessage{
		Type:      msgType,
		From:      from,
		Payload:   payload,
		Timestamp: time.Now().UTC(),
		MessageID: generateMessageID(),
	}
}

// NewErrorMessage creates an error message
func NewErrorMessage(code, message string) []byte {
	msg := ServerMessage{
		Type:      MessageTypeError,
		Timestamp: time.Now().UTC(),
		Payload:   mustMarshal(ErrorMessage{Code: code, Message: message}),
	}
	return mustMarshal(msg)
}

// Helper functions

func generateMessageID() string {
	// Simple ID generation - could be replaced with UUID
	return time.Now().Format("20060102150405") + "-" + randomString(8)
}

func mustMarshal(v interface{}) string {
	data, _ := json.Marshal(v)
	return string(data)
}

func randomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[time.Now().UnixNano()%int64(len(letters))]
	}
	return string(b)
}
ENDOFFILE

# Create client.go (simplified version to avoid the file being too long)
cat > src/internal/relay/client.go << 'ENDOFFILE'
package relay

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gofiber/websocket/v2"
	"github.com/google/uuid"
)

const (
	writeWait         = 10 * time.Second
	pongWait          = 60 * time.Second
	pingPeriod        = (pongWait * 9) / 10
	maxMessageSize    = 512 * 1024
	channelBufferSize = 256
)

type Client struct {
	ID       string
	UserID   string
	DeviceID string

	hub  *Hub
	conn *websocket.Conn
	send chan []byte

	mu         sync.RWMutex
	isClosing  bool
	lastActive time.Time
}

func NewClient(hub *Hub, conn *websocket.Conn, userID, deviceID string) *Client {
	return &Client{
		ID:         uuid.New().String(),
		UserID:     userID,
		DeviceID:   deviceID,
		hub:        hub,
		conn:       conn,
		send:       make(chan []byte, channelBufferSize),
		lastActive: time.Now(),
	}
}

func (c *Client) Start() {
	c.hub.register <- c
	go c.writePump()
	go c.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		c.updateLastActive()
		return nil
	})

	for {
		messageType, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error for user %s: %v", c.UserID, err)
			}
			break
		}

		if messageType != websocket.TextMessage {
			continue
		}

		c.updateLastActive()

		clientMsg, err := ParseMessage(message)
		if err != nil {
			log.Printf("Failed to parse message from user %s: %v", c.UserID, err)
			c.send <- NewErrorMessage("PARSE_ERROR", "Invalid message format")
			continue
		}

		c.processMessage(clientMsg)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) processMessage(msg *ClientMessage) {
	switch msg.Type {
	case MessageTypeText:
		c.handleTextMessage(msg)
	case MessageTypeTyping:
		c.handleTypingIndicator(msg)
	case MessageTypeRead:
		c.handleReadReceipt(msg)
	case MessageTypePresence:
		c.handlePresenceUpdate(msg)
	case MessageTypePing:
		c.handlePing()
	default:
		c.send <- NewErrorMessage("UNKNOWN_TYPE", "Unknown message type")
	}
}

func (c *Client) handleTextMessage(msg *ClientMessage) {
	if msg.To == "" {
		c.send <- NewErrorMessage("MISSING_RECIPIENT", "Recipient ID required")
		return
	}

	relayMsg := &RelayMessage{
		From:     c.UserID,
		To:       msg.To,
		DeviceID: c.DeviceID,
		Type:     msg.Type,
		Payload:  msg.Payload,
	}

	c.hub.relay <- relayMsg

	ctx := context.Background()
	messageID := generateMessageID()
	
	if c.hub.presence != nil {
		c.hub.presence.StoreMessageMetadata(ctx, messageID, c.UserID, msg.To)
	}

	deliveryMsg := NewServerMessage(MessageTypeDelivery, "", messageID)
	if data, err := json.Marshal(deliveryMsg); err == nil {
		c.send <- data
	}
}

func (c *Client) handleTypingIndicator(msg *ClientMessage) {
	if msg.To == "" {
		return
	}

	indicator := &TypingIndicator{
		UserID:   c.UserID,
		IsTyping: msg.Payload == "true",
	}

	relayMsg := &RelayMessage{
		From:    c.UserID,
		To:      msg.To,
		Type:    MessageTypeTyping,
		Payload: mustMarshal(indicator),
	}

	c.hub.relay <- relayMsg
}

func (c *Client) handleReadReceipt(msg *ClientMessage) {
	receipt := &ReadReceipt{
		MessageID: msg.Payload,
		ReadAt:    time.Now().UTC(),
	}

	relayMsg := &RelayMessage{
		From:    c.UserID,
		To:      msg.To,
		Type:    MessageTypeRead,
		Payload: mustMarshal(receipt),
	}

	c.hub.relay <- relayMsg
}

func (c *Client) handlePresenceUpdate(msg *ClientMessage) {
	ctx := context.Background()
	if c.hub.presence != nil {
		c.hub.presence.UpdatePresence(ctx, c.UserID, msg.Payload)
	}
}

func (c *Client) handlePing() {
	pong := NewServerMessage(MessageTypePong, "", "")
	if data, err := json.Marshal(pong); err == nil {
		c.send <- data
	}
}

func (c *Client) updateLastActive() {
	c.mu.Lock()
	c.lastActive = time.Now()
	c.mu.Unlock()
}

func (c *Client) Close() {
	c.mu.Lock()
	if c.isClosing {
		c.mu.Unlock()
		return
	}
	c.isClosing = true
	c.mu.Unlock()

	close(c.send)
}

func (c *Client) GetLastActive() time.Time {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.lastActive
}
ENDOFFILE

# Create hub.go
cat > src/internal/relay/hub.go << 'ENDOFFILE'
package relay

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"chat-e2ee/internal/presence"
)

type RelayMessage struct {
	From     string      `json:"from"`
	To       string      `json:"to"`
	DeviceID string      `json:"device_id"`
	Type     MessageType `json:"type"`
	Payload  string      `json:"payload"`
}

type Hub struct {
	clients    map[string]map[string]*Client
	clientsMu  sync.RWMutex

	relay      chan *RelayMessage
	register   chan *Client
	unregister chan *Client

	presence *presence.Tracker

	stats   *HubStats
	statsMu sync.RWMutex
}

type HubStats struct {
	TotalConnections  int64
	ActiveConnections int
	MessagesRelayed   int64
	LastActivity      time.Time
}

func NewHub(presenceTracker *presence.Tracker) *Hub {
	return &Hub{
		clients:    make(map[string]map[string]*Client),
		relay:      make(chan *RelayMessage, 1000),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		presence:   presenceTracker,
		stats:      &HubStats{},
	}
}

func (h *Hub) Run() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case client := <-h.register:
			h.registerClient(client)

		case client := <-h.unregister:
			h.unregisterClient(client)

		case message := <-h.relay:
			h.relayMessage(message)

		case <-ticker.C:
			h.cleanup()
		}
	}
}

func (h *Hub) registerClient(client *Client) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if _, exists := h.clients[client.UserID]; !exists {
		h.clients[client.UserID] = make(map[string]*Client)
	}

	h.clients[client.UserID][client.DeviceID] = client

	h.updateStats(func(s *HubStats) {
		s.TotalConnections++
		s.ActiveConnections = h.countActiveConnections()
		s.LastActivity = time.Now()
	})

	if h.presence != nil {
		ctx := context.Background()
		h.presence.SetUserOnline(ctx, client.UserID, client.DeviceID)
	}

	log.Printf("Client registered: UserID=%s, DeviceID=%s", client.UserID, client.DeviceID)

	h.deliverPendingMessages(client)
}

func (h *Hub) unregisterClient(client *Client) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if devices, exists := h.clients[client.UserID]; exists {
		if _, exists := devices[client.DeviceID]; exists {
			delete(devices, client.DeviceID)
			client.Close()

			if len(devices) == 0 {
				delete(h.clients, client.UserID)
			}

			h.updateStats(func(s *HubStats) {
				s.ActiveConnections = h.countActiveConnections()
			})

			if h.presence != nil {
				ctx := context.Background()
				if len(devices) == 0 {
					h.presence.SetUserOffline(ctx, client.UserID)
				}
			}

			log.Printf("Client unregistered: UserID=%s, DeviceID=%s", client.UserID, client.DeviceID)
		}
	}
}

func (h *Hub) relayMessage(msg *RelayMessage) {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	if devices, exists := h.clients[msg.To]; exists {
		serverMsg := NewServerMessage(msg.Type, msg.From, msg.Payload)
		data, err := json.Marshal(serverMsg)
		if err != nil {
			log.Printf("Failed to marshal message: %v", err)
			return
		}

		delivered := false
		for deviceID, client := range devices {
			select {
			case client.send <- data:
				delivered = true
				log.Printf("Message relayed: From=%s To=%s Device=%s", msg.From, msg.To, deviceID)
			default:
				log.Printf("Client buffer full: UserID=%s DeviceID=%s", msg.To, deviceID)
			}
		}

		if delivered {
			h.updateStats(func(s *HubStats) {
				s.MessagesRelayed++
				s.LastActivity = time.Now()
			})
		}
	} else {
		if msg.Type == MessageTypeText && h.presence != nil {
			ctx := context.Background()
			h.presence.StorePendingMessage(ctx, msg.To, msg)
		}
		log.Printf("User offline, message stored: To=%s", msg.To)
	}
}

func (h *Hub) deliverPendingMessages(client *Client) {
	if h.presence == nil {
		return
	}

	ctx := context.Background()
	messages := h.presence.GetPendingMessages(ctx, client.UserID)

	for _, msgData := range messages {
		var msg RelayMessage
		if err := json.Unmarshal([]byte(msgData), &msg); err != nil {
			continue
		}

		serverMsg := NewServerMessage(msg.Type, msg.From, msg.Payload)
		if data, err := json.Marshal(serverMsg); err == nil {
			select {
			case client.send <- data:
				log.Printf("Delivered pending message to %s", client.UserID)
			default:
			}
		}
	}

	h.presence.ClearPendingMessages(ctx, client.UserID)
}

func (h *Hub) cleanup() {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	now := time.Now()
	for userID, devices := range h.clients {
		for deviceID, client := range devices {
			if now.Sub(client.GetLastActive()) > 5*time.Minute {
				log.Printf("Removing inactive client: UserID=%s DeviceID=%s", userID, deviceID)
				delete(devices, deviceID)
				client.Close()
			}
		}
		if len(devices) == 0 {
			delete(h.clients, userID)
		}
	}
}

func (h *Hub) GetStats() HubStats {
	h.statsMu.RLock()
	defer h.statsMu.RUnlock()
	return *h.stats
}

func (h *Hub) GetUserClients(userID string) []*Client {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	var clients []*Client
	if devices, exists := h.clients[userID]; exists {
		for _, client := range devices {
			clients = append(clients, client)
		}
	}
	return clients
}

func (h *Hub) BroadcastToUser(userID string, message []byte) {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	if devices, exists := h.clients[userID]; exists {
		for _, client := range devices {
			select {
			case client.send <- message:
			default:
			}
		}
	}
}

func (h *Hub) countActiveConnections() int {
	count := 0
	for _, devices := range h.clients {
		count += len(devices)
	}
	return count
}

func (h *Hub) updateStats(fn func(*HubStats)) {
	h.statsMu.Lock()
	defer h.statsMu.Unlock()
	fn(h.stats)
}
ENDOFFILE

# Create websocket.go
cat > src/internal/relay/websocket.go << 'ENDOFFILE'
package relay

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"time"

	"chat-e2ee/internal/auth"
	"chat-e2ee/internal/presence"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"github.com/redis/go-redis/v9"
)

type Handler struct {
	hub        *Hub
	jwtService *auth.JWTService
}

func NewHandler(hub *Hub, jwtService *auth.JWTService) *Handler {
	return &Handler{
		hub:        hub,
		jwtService: jwtService,
	}
}

func (h *Handler) UpgradeHandler() fiber.Handler {
	return func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			token := c.Query("token")
			if token == "" {
				authHeader := c.Get("Authorization")
				if authHeader != "" {
					parts := strings.Split(authHeader, " ")
					if len(parts) == 2 && parts[0] == "Bearer" {
						token = parts[1]
					}
				}
			}

			if token == "" {
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Missing authentication token",
				})
			}

			claims, err := h.jwtService.ValidateToken(token)
			if err != nil {
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Invalid token",
				})
			}

			if claims.Type != "access" {
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Invalid token type",
				})
			}

			c.Locals("userID", claims.UserID)
			c.Locals("deviceID", claims.DeviceID)

			log.Printf("WebSocket upgrade request from UserID: %s, DeviceID: %s", 
				claims.UserID, claims.DeviceID)

			return c.Next()
		}

		return fiber.ErrUpgradeRequired
	}
}

func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(c *websocket.Conn) {
		userID, ok := c.Locals("userID").(string)
		if !ok || userID == "" {
			log.Println("WebSocket: missing userID")
			c.Close()
			return
		}

		deviceID, ok := c.Locals("deviceID").(string)
		if !ok || deviceID == "" {
			log.Println("WebSocket: missing deviceID")
			c.Close()
			return
		}

		client := NewClient(h.hub, c, userID, deviceID)
		
		log.Printf("New WebSocket connection: UserID=%s, DeviceID=%s, ClientID=%s",
			userID, deviceID, client.ID)

		client.Start()
	}, websocket.Config{
		ReadBufferSize:    1024,
		WriteBufferSize:   1024,
		EnableCompression: true,
	})
}

func (h *Handler) GetStats() fiber.Handler {
	return func(c *fiber.Ctx) error {
		stats := h.hub.GetStats()
		
		var onlineUsers []string
		if h.hub.presence != nil {
			ctx := c.Context()
			onlineUsers, _ = h.hub.presence.GetOnlineUsers(ctx)
		}

		return c.JSON(fiber.Map{
			"websocket": fiber.Map{
				"total_connections":  stats.TotalConnections,
				"active_connections": stats.ActiveConnections,
				"messages_relayed":   stats.MessagesRelayed,
				"last_activity":      stats.LastActivity,
			},
			"users": fiber.Map{
				"online_count": len(onlineUsers),
				"online_users": onlineUsers,
			},
		})
	}
}

func (h *Handler) SendSystemMessage(userID string, message interface{}) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}

	h.hub.BroadcastToUser(userID, data)
	return nil
}

func (h *Handler) IsUserOnline(userID string) bool {
	clients := h.hub.GetUserClients(userID)
	return len(clients) > 0
}

func (h *Handler) DisconnectUser(userID string) {
	clients := h.hub.GetUserClients(userID)
	for _, client := range clients {
		client.Close()
	}
}

func CreateRelayService(redisClient *redis.Client, jwtService *auth.JWTService) (*Handler, *Hub) {
	presenceTracker := presence.NewTracker(redisClient)
	hub := NewHub(presenceTracker)

	go hub.Run()

	handler := NewHandler(hub, jwtService)

	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()

		for range ticker.C {
			ctx := context.Background()
			if err := presenceTracker.CleanupInactive(ctx, 10*time.Minute); err != nil {
				log.Printf("Presence cleanup error: %v", err)
			}
		}
	}()

	return handler, hub
}
ENDOFFILE

# Create tracker.go
cat > src/internal/presence/tracker.go << 'ENDOFFILE'
package presence

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Tracker struct {
	redis *redis.Client
}

func NewTracker(redisClient *redis.Client) *Tracker {
	return &Tracker{
		redis: redisClient,
	}
}

func (t *Tracker) SetUserOnline(ctx context.Context, userID, deviceID string) error {
	pipe := t.redis.Pipeline()

	userKey := fmt.Sprintf("presence:user:%s", userID)
	pipe.HSet(ctx, userKey, map[string]interface{}{
		"status":    "online",
		"last_seen": time.Now().Unix(),
	})
	pipe.Expire(ctx, userKey, 24*time.Hour)

	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	pipe.SAdd(ctx, deviceKey, deviceID)
	pipe.Expire(ctx, deviceKey, 24*time.Hour)

	pipe.SAdd(ctx, "presence:online_users", userID)

	_, err := pipe.Exec(ctx)
	return err
}

func (t *Tracker) SetUserOffline(ctx context.Context, userID string) error {
	pipe := t.redis.Pipeline()

	userKey := fmt.Sprintf("presence:user:%s", userID)
	pipe.HSet(ctx, userKey, map[string]interface{}{
		"status":    "offline",
		"last_seen": time.Now().Unix(),
	})

	pipe.SRem(ctx, "presence:online_users", userID)

	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	pipe.Del(ctx, deviceKey)

	_, err := pipe.Exec(ctx)
	return err
}

func (t *Tracker) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	return t.redis.SIsMember(ctx, "presence:online_users", userID).Result()
}

func (t *Tracker) GetUserStatus(ctx context.Context, userID string) (map[string]string, error) {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HGetAll(ctx, userKey).Result()
}

func (t *Tracker) GetOnlineUsers(ctx context.Context) ([]string, error) {
	return t.redis.SMembers(ctx, "presence:online_users").Result()
}

func (t *Tracker) UpdatePresence(ctx context.Context, userID, status string) error {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HSet(ctx, userKey, "status", status).Err()
}

func (t *Tracker) StorePendingMessage(ctx context.Context, userID string, message interface{}) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}

	key := fmt.Sprintf("pending:messages:%s", userID)
	pipe := t.redis.Pipeline()
	
	pipe.LPush(ctx, key, data)
	pipe.LTrim(ctx, key, 0, 99)
	pipe.Expire(ctx, key, 7*24*time.Hour)

	_, err = pipe.Exec(ctx)
	return err
}

func (t *Tracker) GetPendingMessages(ctx context.Context, userID string) ([]string, error) {
	key := fmt.Sprintf("pending:messages:%s", userID)
	messages, err := t.redis.LRange(ctx, key, 0, -1).Result()
	if err != nil {
		return nil, err
	}
	
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}
	
	return messages, nil
}

func (t *Tracker) ClearPendingMessages(ctx context.Context, userID string) error {
	key := fmt.Sprintf("pending:messages:%s", userID)
	return t.redis.Del(ctx, key).Err()
}

func (t *Tracker) StoreMessageMetadata(ctx context.Context, messageID, from, to string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	data := map[string]interface{}{
		"from":      from,
		"to":        to,
		"timestamp": time.Now().Unix(),
		"delivered": false,
		"read":      false,
	}

	pipe := t.redis.Pipeline()
	pipe.HSet(ctx, key, data)
	pipe.Expire(ctx, key, 24*time.Hour)

	_, err := pipe.Exec(ctx)
	return err
}

func (t *Tracker) MarkMessageDelivered(ctx context.Context, messageID string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	return t.redis.HSet(ctx, key, map[string]interface{}{
		"delivered":    true,
		"delivered_at": time.Now().Unix(),
	}).Err()
}

func (t *Tracker) MarkMessageRead(ctx context.Context, messageID string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	return t.redis.HSet(ctx, key, map[string]interface{}{
		"read":    true,
		"read_at": time.Now().Unix(),
	}).Err()
}

func (t *Tracker) GetActiveDevices(ctx context.Context, userID string) ([]string, error) {
	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	return t.redis.SMembers(ctx, deviceKey).Result()
}

func (t *Tracker) Heartbeat(ctx context.Context, userID string) error {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HSet(ctx, userKey, "last_seen", time.Now().Unix()).Err()
}

func (t *Tracker) CleanupInactive(ctx context.Context, inactiveThreshold time.Duration) error {
	onlineUsers, err := t.GetOnlineUsers(ctx)
	if err != nil {
		return err
	}

	now := time.Now().Unix()
	threshold := now - int64(inactiveThreshold.Seconds())

	for _, userID := range onlineUsers {
		status, err := t.GetUserStatus(ctx, userID)
		if err != nil {
			continue
		}

		if lastSeenStr, ok := status["last_seen"]; ok {
			var lastSeen int64
			fmt.Sscanf(lastSeenStr, "%d", &lastSeen)
			
			if lastSeen < threshold {
				t.SetUserOffline(ctx, userID)
			}
		}
	}

	return nil
}
ENDOFFILE

# Make script executable
chmod +x scripts/test-websocket.sh

echo "✅ Phase 3 files created successfully!"

# Update dependencies
echo "Updating Go dependencies..."
cd src
go get github.com/gofiber/websocket/v2@latest
go mod tidy

# Build to check for errors
echo "Building to check for compilation errors..."
if go build ./cmd/server/main.go; then
    echo "✅ Build successful!"
    rm main  # Clean up binary
else
    echo "❌ Build failed! Check errors above."
fi

echo ""
echo "Next steps:"
echo "1. Rebuild backend: docker-compose build backend"
echo "2. Restart backend: ./scripts/restart.sh"
echo "3. Test WebSocket: ./scripts/test-websocket.sh"