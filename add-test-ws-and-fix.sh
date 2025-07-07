#!/bin/bash

echo "🔧 Agregando endpoint de test y arreglando el handler principal"

# 1. Primero, agregar el endpoint de test en main.go
echo -e "\n1. Agregando endpoint de test WebSocket en main.go..."

# Buscar dónde agregar el endpoint (justo antes de app.Listen)
sed -i '/app.Listen(addr)/i\
	// Test WebSocket endpoint\
	app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {\
		log.Println("[TEST-WS] Handler started")\
		defer log.Println("[TEST-WS] Handler ended")\
		\
		// Send welcome message\
		c.WriteMessage(websocket.TextMessage, []byte("Welcome to test WebSocket!"))\
		\
		// Simple echo loop\
		for {\
			mt, msg, err := c.ReadMessage()\
			if err != nil {\
				log.Printf("[TEST-WS] Error: %v", err)\
				break\
			}\
			log.Printf("[TEST-WS] Received: %s", string(msg))\
			c.WriteMessage(mt, append([]byte("Echo: "), msg...))\
		}\
	}))\
	log.Println("✅ Test WebSocket endpoint registered at /test-ws")\
' src/cmd/server/main.go

# 2. Ahora, vamos a reescribir el WebSocketHandler principal de manera más simple
echo -e "\n2. Reescribiendo el WebSocketHandler principal..."

cat > /tmp/new_websocket_handler.go << 'ENDOFFILE'
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
		log.Printf("[DEBUG] WebSocketHandler started")
		defer log.Printf("[DEBUG] WebSocketHandler ended")
		
		userID, ok := c.Locals("userID").(string)
		if !ok || userID == "" {
			log.Println("[ERROR] WebSocket: missing userID")
			return
		}

		deviceID, ok := c.Locals("deviceID").(string)
		if !ok || deviceID == "" {
			log.Println("[ERROR] WebSocket: missing deviceID")
			return
		}

		log.Printf("[DEBUG] Creating client for UserID=%s, DeviceID=%s", userID, deviceID)
		
		// Send initial welcome message
		welcome := map[string]interface{}{
			"type": "connected",
			"message": "WebSocket connection established",
			"timestamp": time.Now().Unix(),
		}
		if data, err := json.Marshal(welcome); err == nil {
			c.WriteMessage(websocket.TextMessage, data)
		}
		
		// Create done channel
		done := make(chan bool)
		
		// Start a simple goroutine for reading
		go func() {
			defer close(done)
			
			for {
				messageType, p, err := c.ReadMessage()
				if err != nil {
					log.Printf("[DEBUG] Read error: %v", err)
					return
				}
				
				if messageType == websocket.TextMessage {
					log.Printf("[DEBUG] Received: %s", string(p))
					
					// Parse message
					var msg map[string]interface{}
					if err := json.Unmarshal(p, &msg); err == nil {
						msgType, _ := msg["type"].(string)
						
						switch msgType {
						case "ping":
							pong := map[string]interface{}{
								"type": "pong",
								"timestamp": time.Now().Unix(),
							}
							if data, err := json.Marshal(pong); err == nil {
								c.WriteMessage(websocket.TextMessage, data)
							}
						default:
							// Echo for now
							response := map[string]interface{}{
								"type": "echo",
								"original": msg,
								"timestamp": time.Now().Unix(),
							}
							if data, err := json.Marshal(response); err == nil {
								c.WriteMessage(websocket.TextMessage, data)
							}
						}
					}
				}
			}
		}()
		
		// Wait for connection to close
		<-done
		log.Printf("[DEBUG] Connection closed for UserID=%s", userID)
		
	}, websocket.Config{
		ReadBufferSize:    4096,
		WriteBufferSize:   4096,
		EnableCompression: false,
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

# 3. Reemplazar todo el archivo websocket.go
echo -e "\n3. Reemplazando websocket.go con versión simplificada..."
cp src/internal/relay/websocket.go src/internal/relay/websocket.go.bak2
cp /tmp/new_websocket_handler.go src/internal/relay/websocket.go

# 4. Rebuild
echo -e "\n4. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar"
    exit 1
fi
docker-compose restart backend
cd ..

echo -e "\n5. Esperando que inicie..."
sleep 5

echo -e "\n✅ Listo para probar!"
echo ""
echo "PRUEBA 1 - Test endpoint simple (sin autenticación):"
echo "wscat -c 'ws://localhost:8080/test-ws'"
echo ""
echo "PRUEBA 2 - Endpoint principal con autenticación:"
echo "source /tmp/chat-e2ee-tokens.txt && wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "Ver logs en otra terminal:"
echo "./scripts/logs.sh backend -f | grep -E '(TEST-WS|DEBUG|WebSocket)'"