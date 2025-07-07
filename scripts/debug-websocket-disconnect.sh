#!/bin/bash

# Script para agregar más logging y debuggear por qué el WebSocket se desconecta

echo "🔍 Agregando logging de debug al WebSocket..."

# 1. Modificar client.go para agregar más logging
cat > src/internal/relay/client_debug.go << 'ENDOFFILE'
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
	log.Printf("[DEBUG] Client.Start() called for UserID=%s, DeviceID=%s", c.UserID, c.DeviceID)
	c.hub.register <- c
	go c.writePump()
	go c.readPump()
}

func (c *Client) readPump() {
	log.Printf("[DEBUG] readPump started for UserID=%s", c.UserID)
	defer func() {
		log.Printf("[DEBUG] readPump ending for UserID=%s", c.UserID)
		c.hub.unregister <- c
		c.conn.Close()
	}()

	// Configure WebSocket
	c.conn.SetReadLimit(maxMessageSize)
	if err := c.conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
		log.Printf("[ERROR] Failed to set read deadline: %v", err)
		return
	}
	
	c.conn.SetPongHandler(func(string) error {
		log.Printf("[DEBUG] Pong received from UserID=%s", c.UserID)
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		c.updateLastActive()
		return nil
	})

	for {
		messageType, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[ERROR] WebSocket error for user %s: %v", c.UserID, err)
			} else {
				log.Printf("[DEBUG] WebSocket closed for user %s: %v", c.UserID, err)
			}
			break
		}

		log.Printf("[DEBUG] Message received from UserID=%s, type=%d, size=%d", c.UserID, messageType, len(message))

		if messageType != websocket.TextMessage {
			continue
		}

		c.updateLastActive()

		clientMsg, err := ParseMessage(message)
		if err != nil {
			log.Printf("[ERROR] Failed to parse message from user %s: %v", c.UserID, err)
			c.send <- NewErrorMessage("PARSE_ERROR", "Invalid message format")
			continue
		}

		c.processMessage(clientMsg)
	}
}

func (c *Client) writePump() {
	log.Printf("[DEBUG] writePump started for UserID=%s", c.UserID)
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		log.Printf("[DEBUG] writePump ending for UserID=%s", c.UserID)
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			if err := c.conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
				log.Printf("[ERROR] Failed to set write deadline: %v", err)
				return
			}
			
			if !ok {
				log.Printf("[DEBUG] Send channel closed for UserID=%s", c.UserID)
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			log.Printf("[DEBUG] Sending message to UserID=%s, size=%d", c.UserID, len(message))
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				log.Printf("[ERROR] Failed to write message: %v", err)
				return
			}

		case <-ticker.C:
			log.Printf("[DEBUG] Sending ping to UserID=%s", c.UserID)
			if err := c.conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
				log.Printf("[ERROR] Failed to set write deadline for ping: %v", err)
				return
			}
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				log.Printf("[ERROR] Failed to send ping: %v", err)
				return
			}
		}
	}
}

func (c *Client) processMessage(msg *ClientMessage) {
	log.Printf("[DEBUG] Processing message type=%s from UserID=%s", msg.Type, c.UserID)
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
	log.Printf("[DEBUG] Handling ping from UserID=%s", c.UserID)
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
	log.Printf("[DEBUG] Client.Close() called for UserID=%s", c.UserID)
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

# 2. Reemplazar el archivo original
mv src/internal/relay/client_debug.go src/internal/relay/client.go

# 3. Verificar que no hay test de WebSocket que esté usando el puerto
echo -e "\n🔍 Verificando procesos en el puerto 8080..."
lsof -i :8080 2>/dev/null || echo "Puerto 8080 libre"

# 4. Rebuild y restart
echo -e "\n🔨 Rebuilding backend con debug logging..."
cd docker
docker-compose build backend
docker-compose restart backend

cd ..
sleep 3

echo -e "\n✅ Debug logging agregado!"
echo ""
echo "Ahora intenta conectarte nuevamente y verás más detalles:"
echo "1. En una terminal: ./scripts/logs.sh backend -f | grep DEBUG"
echo "2. En otra terminal: wscat -c \"ws://localhost:8080/ws?token=TU_TOKEN\""