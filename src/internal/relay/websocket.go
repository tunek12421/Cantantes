package relay

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"

	"chat-e2ee/internal/auth"
	"chat-e2ee/internal/presence"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type Handler struct {
	hub        *Hub
	jwtService *auth.JWTService
	
	connMu sync.RWMutex
	conns  map[string]*websocket.Conn
}

func NewHandler(hub *Hub, jwtService *auth.JWTService) *Handler {
	return &Handler{
		hub:        hub,
		jwtService: jwtService,
		conns:      make(map[string]*websocket.Conn),
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

			log.Printf("[WebSocket] Upgrade request authenticated - UserID: %s, DeviceID: %s", 
				claims.UserID, claims.DeviceID)

			return c.Next()
		}

		return fiber.ErrUpgradeRequired
	}
}

func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(ws *websocket.Conn) {
		userID := ws.Locals("userID").(string)
		deviceID := ws.Locals("deviceID").(string)
		connID := uuid.New().String()
		
		log.Printf("[WebSocket] New connection: UserID=%s, DeviceID=%s, ConnID=%s", userID, deviceID, connID)
		
		// Store connection
		h.connMu.Lock()
		h.conns[connID] = ws
		h.connMu.Unlock()
		
		// Create send channel
		send := make(chan []byte, 256)
		
		// Register with hub
		if h.hub != nil {
			client := &Client{
				ID:         connID,
				UserID:     userID,
				DeviceID:   deviceID,
				hub:        h.hub,
				send:       send,
				lastActive: time.Now(),
			}
			h.hub.register <- client
		}
		
		// Send welcome message
		welcome := map[string]interface{}{
			"type": "connected",
			"message": "Connected to Chat E2EE WebSocket",
			"timestamp": time.Now().Unix(),
			"user_id": userID,
			"device_id": deviceID,
		}
		
		if data, err := json.Marshal(welcome); err == nil {
			ws.WriteMessage(websocket.TextMessage, data)
		}
		
		// Start write pump
		stopWrite := make(chan bool)
		go h.writePump(ws, send, stopWrite)
		
		// Read pump (blocking)
		h.readPump(ws, userID, deviceID, send)
		
		// Cleanup
		close(stopWrite)
		close(send)
		
		h.connMu.Lock()
		delete(h.conns, connID)
		h.connMu.Unlock()
		
		// Unregister from hub
		if h.hub != nil {
			client := &Client{
				ID:       connID,
				UserID:   userID,
				DeviceID: deviceID,
				hub:      h.hub,
			}
			h.hub.unregister <- client
		}
		
		log.Printf("[WebSocket] Connection closed: UserID=%s, ConnID=%s", userID, connID)
	})
}

func (h *Handler) readPump(ws *websocket.Conn, userID, deviceID string, send chan []byte) {
	defer ws.Close()
	
	ws.SetReadLimit(512 * 1024)
	ws.SetReadDeadline(time.Now().Add(60 * time.Second))
	ws.SetPongHandler(func(string) error {
		ws.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	
	for {
		messageType, message, err := ws.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WebSocket] Error: %v", err)
			}
			break
		}
		
		if messageType == websocket.TextMessage {
			log.Printf("[WebSocket] Received from %s: %s", userID, string(message))
			
			var msg ClientMessage
			if err := json.Unmarshal(message, &msg); err != nil {
				log.Printf("[WebSocket] Parse error: %v", err)
				continue
			}
			
			switch msg.Type {
			case "ping":
				pong := map[string]interface{}{
					"type": "pong",
					"timestamp": time.Now().Unix(),
				}
				if data, err := json.Marshal(pong); err == nil {
					select {
					case send <- data:
						log.Printf("[WebSocket] Pong queued")
					default:
						log.Printf("[WebSocket] Send buffer full")
					}
				}
				
			case "message":
				if msg.To != "" && h.hub != nil {
					relayMsg := &RelayMessage{
						From:     userID,
						To:       msg.To,
						DeviceID: deviceID,
						Type:     MessageTypeText,
						Payload:  msg.Payload,
					}
					h.hub.relay <- relayMsg
				}
				
			default:
				log.Printf("[WebSocket] Unknown message type: %s", msg.Type)
			}
		}
	}
}

func (h *Handler) writePump(ws *websocket.Conn, send chan []byte, stop chan bool) {
	ticker := time.NewTicker(54 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case message, ok := <-send:
			ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
			
			if !ok {
				ws.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			
			if err := ws.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			
		case <-ticker.C:
			ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := ws.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
			
		case <-stop:
			return
		}
	}
}

func (h *Handler) GetStats() fiber.Handler {
	return func(c *fiber.Ctx) error {
		h.connMu.RLock()
		activeConns := len(h.conns)
		h.connMu.RUnlock()
		
		stats := h.hub.GetStats()
		
		var onlineUsers []string
		if h.hub.presence != nil {
			ctx := c.Context()
			onlineUsers, _ = h.hub.presence.GetOnlineUsers(ctx)
		}

		return c.JSON(fiber.Map{
			"websocket": fiber.Map{
				"total_connections":  stats.TotalConnections,
				"active_connections": activeConns,
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

func CreateRelayService(redisClient *redis.Client, jwtService *auth.JWTService) (*Handler, *Hub) {
	log.Printf("[WebSocket] Creating relay service...")
	
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
	
	log.Printf("[WebSocket] Relay service created successfully")
	return handler, hub
}
