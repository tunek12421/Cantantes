#!/bin/bash

# Fix the specific compilation errors in client.go

echo "🔧 Fixing client.go compilation errors..."

# Let's check what's at lines 174 and 190
echo "Current content around line 174:"
sed -n '170,180p' src/internal/relay/client.go

echo -e "\nCurrent content around line 190:"
sed -n '185,195p' src/internal/relay/client.go

# Now let's fix the handleTypingIndicator and handleReadReceipt functions
# We need to find these functions and fix them properly

cat > src/internal/relay/client_fix.go << 'ENDOFFILE'
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

	// Properly marshal the indicator
	indicatorJSON, _ := json.Marshal(indicator)

	relayMsg := &RelayMessage{
		From:    c.UserID,
		To:      msg.To,
		Type:    MessageTypeTyping,
		Payload: string(indicatorJSON),
	}

	c.hub.relay <- relayMsg
}

func (c *Client) handleReadReceipt(msg *ClientMessage) {
	receipt := &ReadReceipt{
		MessageID: msg.Payload,
		ReadAt:    time.Now().UTC(),
	}

	// Properly marshal the receipt
	receiptJSON, _ := json.Marshal(receipt)

	relayMsg := &RelayMessage{
		From:    c.UserID,
		To:      msg.To,
		Type:    MessageTypeRead,
		Payload: string(receiptJSON),
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

# Replace the original client.go with the fixed version
mv src/internal/relay/client_fix.go src/internal/relay/client.go

echo "✅ client.go fixed!"

# Also ensure the HandleWebSocket method exists in websocket.go
if ! grep -q "HandleWebSocket" src/internal/relay/websocket.go; then
    echo "Adding HandleWebSocket method..."
    cat >> src/internal/relay/websocket.go << 'ENDOFFILE'

// HandleWebSocket handles a new WebSocket connection
func (h *Handler) HandleWebSocket(conn *websocket.Conn, userID, deviceID string) {
	client := NewClient(h.hub, conn, userID, deviceID)
	client.Start()
}
ENDOFFILE
fi

echo "✅ All client.go errors should be fixed now!"
echo ""
echo "Rebuild and test:"
echo "cd docker && docker-compose build backend && docker-compose restart backend"