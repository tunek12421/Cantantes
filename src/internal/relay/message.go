package relay

import (
	"encoding/json"
	"time"
	"math/rand"
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
	errMsg := ErrorMessage{Code: code, Message: message}
	payload, _ := json.Marshal(errMsg)
	
	msg := ServerMessage{
		Type:      MessageTypeError,
		Timestamp: time.Now().UTC(),
		Payload:   string(payload),
	}
	
	data, _ := json.Marshal(msg)
	return data
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
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}
