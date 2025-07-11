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
	if conn == nil {
		log.Printf("[ERROR] NewClient called with nil connection for UserID=%s", userID)
		return nil
	}
	
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
	if c == nil || c.conn == nil {
		log.Printf("[ERROR] Client.Start() called with nil client or connection")
		return
	}
	
	log.Printf("[DEBUG] Client.Start() called for UserID=%s, DeviceID=%s, conn=%p", c.UserID, c.DeviceID, c.conn)
	
	c.hub.register <- c
	log.Printf("[DEBUG] Client sent to hub.register channel")
	
	go c.writePump()
	log.Printf("[DEBUG] writePump goroutine started")
	
	go c.readPump()
	log.Printf("[DEBUG] readPump goroutine started")
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
	defer c.mu.Unlock()
	
	if c.isClosing {
		log.Printf("[DEBUG] Client already closing for UserID=%s", c.UserID)
		return
	}
	c.isClosing = true
	
	// Solo cerrar el canal si no es nil
	if c.send != nil {
		// Verificar si el canal ya está cerrado antes de cerrarlo
		select {
		case _, ok := <-c.send:
			if !ok {
				log.Printf("[DEBUG] Channel already closed for UserID=%s", c.UserID)
				return
			}
		default:
			close(c.send)
			log.Printf("[DEBUG] Channel closed for UserID=%s", c.UserID)
		}
	}
}

func (c *Client) GetLastActive() time.Time {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.lastActive
}
// Agregar estos métodos alternativos a client.go

func (c *Client) readPumpWithConn(conn *websocket.Conn) {
	log.Printf("[DEBUG] readPumpWithConn started for UserID=%s, conn=%p", c.UserID, conn)
	
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[PANIC] readPumpWithConn panic for UserID=%s: %v", c.UserID, r)
		}
		log.Printf("[DEBUG] readPumpWithConn ending for UserID=%s", c.UserID)
		conn.Close()
	}()

	// Configure WebSocket
	conn.SetReadLimit(maxMessageSize)
	if err := conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
		log.Printf("[ERROR] Failed to set read deadline: %v (conn=%p)", err, conn)
		return
	}
	
	conn.SetPongHandler(func(string) error {
		log.Printf("[DEBUG] Pong received from UserID=%s", c.UserID)
		if err := conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
			log.Printf("[ERROR] Failed to update read deadline: %v", err)
			return err
		}
		c.updateLastActive()
		return nil
	})

	log.Printf("[DEBUG] WebSocket configured, entering read loop for UserID=%s", c.UserID)

	for {
		messageType, message, err := conn.ReadMessage()
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
			log.Printf("[DEBUG] Ignoring non-text message type %d", messageType)
			continue
		}

		c.updateLastActive()

		clientMsg, err := ParseMessage(message)
		if err != nil {
			log.Printf("[ERROR] Failed to parse message from user %s: %v", c.UserID, err)
			select {
			case c.send <- NewErrorMessage("PARSE_ERROR", "Invalid message format"):
			default:
				log.Printf("[WARN] Send buffer full for user %s", c.UserID)
			}
			continue
		}

		c.processMessage(clientMsg)
	}
}

func (c *Client) writePumpWithConn(conn *websocket.Conn) {
	log.Printf("[DEBUG] writePumpWithConn started for UserID=%s, conn=%p", c.UserID, conn)
	ticker := time.NewTicker(pingPeriod)
	
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[PANIC] writePumpWithConn panic for UserID=%s: %v", c.UserID, r)
		}
		log.Printf("[DEBUG] writePumpWithConn ending for UserID=%s", c.UserID)
		ticker.Stop()
		conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			if err := conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
				log.Printf("[ERROR] Failed to set write deadline: %v", err)
				return
			}
			
			if !ok {
				log.Printf("[DEBUG] Send channel closed for UserID=%s", c.UserID)
				conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			log.Printf("[DEBUG] Sending message to UserID=%s, size=%d", c.UserID, len(message))
			if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
				log.Printf("[ERROR] Failed to write message: %v", err)
				return
			}

		case <-ticker.C:
			log.Printf("[DEBUG] Sending ping to UserID=%s", c.UserID)
			if err := conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
				log.Printf("[ERROR] Failed to set write deadline for ping: %v", err)
				return
			}
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				log.Printf("[ERROR] Failed to send ping: %v", err)
				return
			}
		}
	}
}

// GetID returns the client ID
func (c *Client) GetID() string {
	return c.ID
}

// GetUserID returns the user ID
func (c *Client) GetUserID() string {
	return c.UserID
}

// GetDeviceID returns the device ID  
func (c *Client) GetDeviceID() string {
	return c.DeviceID
}

// Send sends a message to the client
func (c *Client) Send(message []byte) {
	select {
	case c.send <- message:
	default:
		log.Printf("[WebSocket] Send buffer full for user %s", c.UserID)
	}
}
