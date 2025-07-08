#!/bin/bash

echo "🚀 Fix completo para WebSocket - Fase 3"
echo "======================================="

# 1. Primero, arreglar el import faltante en main.go
echo -e "\n1. Arreglando import de websocket en main.go..."
sed -i '/github.com\/gofiber\/fiber\/v2\/middleware\/recover/a\\t"github.com/gofiber/websocket/v2"' src/cmd/server/main.go

# 2. Crear un WebSocket handler simplificado que funcione
echo -e "\n2. Creando nuevo websocket.go simplificado..."
cat > src/internal/relay/websocket_simple.go << 'ENDOFFILE'
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
			// Get token from query params or header
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

			// Validate token
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

			// Store in locals for the websocket handler
			c.Locals("userID", claims.UserID)
			c.Locals("deviceID", claims.DeviceID)

			log.Printf("[WebSocket] Upgrade request from UserID: %s, DeviceID: %s", 
				claims.UserID, claims.DeviceID)

			return c.Next()
		}

		return fiber.ErrUpgradeRequired
	}
}

func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(conn *websocket.Conn) {
		// Get user info from locals
		userID := conn.Locals("userID").(string)
		deviceID := conn.Locals("deviceID").(string)
		
		log.Printf("[WebSocket] New connection: UserID=%s, DeviceID=%s", userID, deviceID)
		
		// Create a simple client representation
		client := &SimpleClient{
			UserID:   userID,
			DeviceID: deviceID,
			conn:     conn,
			hub:      h.hub,
			send:     make(chan []byte, 256),
		}
		
		// Register with hub
		h.hub.register <- &Client{
			ID:       deviceID,
			UserID:   userID,
			DeviceID: deviceID,
			hub:      h.hub,
			send:     client.send,
		}
		
		// Send welcome message
		welcome := map[string]interface{}{
			"type": "connected",
			"message": "Connected to Chat E2EE",
			"timestamp": time.Now().Unix(),
		}
		if data, err := json.Marshal(welcome); err == nil {
			conn.WriteMessage(websocket.TextMessage, data)
		}
		
		// Start handling messages
		go client.writePump()
		client.readPump()
		
		// Cleanup on disconnect
		h.hub.unregister <- &Client{
			ID:       deviceID,
			UserID:   userID,
			DeviceID: deviceID,
		}
		close(client.send)
		
		log.Printf("[WebSocket] Connection closed: UserID=%s", userID)
	})
}

// SimpleClient handles WebSocket connection directly
type SimpleClient struct {
	UserID   string
	DeviceID string
	conn     *websocket.Conn
	hub      *Hub
	send     chan []byte
}

func (c *SimpleClient) readPump() {
	defer c.conn.Close()
	
	c.conn.SetReadLimit(512 * 1024)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	
	for {
		messageType, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WebSocket] Error: %v", err)
			}
			break
		}
		
		if messageType == websocket.TextMessage {
			log.Printf("[WebSocket] Received from %s: %s", c.UserID, string(message))
			
			// Parse message
			var msg ClientMessage
			if err := json.Unmarshal(message, &msg); err != nil {
				log.Printf("[WebSocket] Parse error: %v", err)
				continue
			}
			
			// Handle different message types
			switch msg.Type {
			case "ping":
				pong := map[string]interface{}{
					"type": "pong",
					"timestamp": time.Now().Unix(),
				}
				if data, err := json.Marshal(pong); err == nil {
					c.send <- data
				}
				
			case "message":
				// Relay message to recipient
				if msg.To != "" {
					relayMsg := &RelayMessage{
						From:     c.UserID,
						To:       msg.To,
						DeviceID: c.DeviceID,
						Type:     MessageTypeText,
						Payload:  msg.Payload,
					}
					c.hub.relay <- relayMsg
				}
				
			default:
				log.Printf("[WebSocket] Unknown message type: %s", msg.Type)
			}
		}
	}
}

func (c *SimpleClient) writePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
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

func CreateRelayService(redisClient *redis.Client, jwtService *auth.JWTService) (*Handler, *Hub) {
	presenceTracker := presence.NewTracker(redisClient)
	hub := NewHub(presenceTracker)
	
	// Start hub
	go hub.Run()
	
	handler := NewHandler(hub, jwtService)
	
	// Cleanup inactive users periodically
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

# 3. Hacer backup y reemplazar
echo -e "\n3. Reemplazando websocket.go..."
mv src/internal/relay/websocket.go src/internal/relay/websocket.go.bak3
mv src/internal/relay/websocket_simple.go src/internal/relay/websocket.go

# 4. Modificar client.go para que sea más simple
echo -e "\n4. Actualizando client.go para compatibilidad..."
cat >> src/internal/relay/client.go << 'ENDOFFILE'

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
ENDOFFILE

# 5. Verificar que el test endpoint esté en main.go
echo -e "\n5. Verificando test endpoint..."
if ! grep -q "test-ws" src/cmd/server/main.go; then
    echo "Agregando test endpoint..."
    # Agregar justo antes de app.Listen
    sed -i '/if err := app.Listen(addr); err != nil {/i\
	// Test WebSocket endpoint\
	app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {\
		log.Println("[TEST-WS] New connection")\
		defer log.Println("[TEST-WS] Connection closed")\
		\
		// Send welcome\
		c.WriteMessage(websocket.TextMessage, []byte("Welcome to test WebSocket!"))\
		\
		// Echo loop\
		for {\
			mt, msg, err := c.ReadMessage()\
			if err != nil {\
				log.Printf("[TEST-WS] Read error: %v", err)\
				break\
			}\
			log.Printf("[TEST-WS] Received: %s", string(msg))\
			\
			// Echo back\
			if err := c.WriteMessage(mt, append([]byte("Echo: "), msg...)); err != nil {\
				log.Printf("[TEST-WS] Write error: %v", err)\
				break\
			}\
		}\
	}))\
	log.Println("✅ Test WebSocket endpoint registered at /test-ws")\
' src/cmd/server/main.go
fi

# 6. Rebuild
echo -e "\n6. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar. Verificando el problema..."
    cd ..
    
    # Verificar imports
    echo -e "\nImports en main.go:"
    grep -A 20 "^import" src/cmd/server/main.go | grep websocket
    
    exit 1
fi

docker-compose restart backend
cd ..

echo -e "\n7. Esperando que el servicio inicie..."
sleep 5

# 8. Verificar que el servicio está corriendo
echo -e "\n8. Verificando servicio..."
curl -s http://localhost:8080/health | jq '.'

echo -e "\n✅ Fix completo aplicado!"
echo ""
echo "=== PRUEBAS ==="
echo ""
echo "1. Test endpoint (sin auth):"
echo "   wscat -c 'ws://localhost:8080/test-ws'"
echo ""
echo "2. Endpoint principal con auth:"
echo "   source /tmp/chat-e2ee-tokens.txt"
echo "   wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "3. Verificar stats:"
echo "   source /tmp/chat-e2ee-tokens.txt"
echo "   curl -H \"Authorization: Bearer \$ACCESS_TOKEN\" http://localhost:8080/api/v1/ws/stats | jq '.'"
echo ""
echo "4. Ver logs:"
echo "   ./scripts/logs.sh backend -f | grep -E '(WebSocket|TEST-WS)'"