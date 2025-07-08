#!/bin/bash

echo "🔍 Diagnosticando y arreglando WebSocket..."
echo "========================================="

# 1. Verificar qué está pasando en los logs después de la conexión
echo -e "\n1. Verificando logs completos de la última conexión..."
./scripts/logs.sh backend | tail -50 | grep -A 10 "New WebSocket connection"

# 2. Verificar si el test endpoint se agregó
echo -e "\n2. Verificando si el endpoint /test-ws existe en main.go..."
grep -n "test-ws" src/cmd/server/main.go || echo "❌ No se encontró el endpoint /test-ws"

# 3. Crear un handler más simple y con más logging
echo -e "\n3. Creando handler simplificado con más debug..."
cat > src/internal/relay/websocket_debug.go << 'ENDOFFILE'
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
	"github.com/google/uuid"
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
		log.Printf("[WebSocket] UpgradeHandler called")
		
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
				log.Printf("[WebSocket] Missing authentication token")
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Missing authentication token",
				})
			}

			// Validate token
			claims, err := h.jwtService.ValidateToken(token)
			if err != nil {
				log.Printf("[WebSocket] Invalid token: %v", err)
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Invalid token",
				})
			}

			if claims.Type != "access" {
				log.Printf("[WebSocket] Invalid token type: %s", claims.Type)
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Invalid token type",
				})
			}

			// Store in locals for the websocket handler
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
	return websocket.New(func(conn *websocket.Conn) {
		log.Printf("[WebSocket] Handler started, conn=%p", conn)
		
		// Get user info from locals
		userID, ok := conn.Locals("userID").(string)
		if !ok {
			log.Printf("[WebSocket] ERROR: No userID in locals")
			return
		}
		
		deviceID, ok := conn.Locals("deviceID").(string) 
		if !ok {
			log.Printf("[WebSocket] ERROR: No deviceID in locals")
			return
		}
		
		log.Printf("[WebSocket] Connection established - UserID: %s, DeviceID: %s", userID, deviceID)
		
		// Create client ID
		clientID := uuid.New().String()
		
		// Register with hub
		client := &Client{
			ID:       clientID,
			UserID:   userID,
			DeviceID: deviceID,
			hub:      h.hub,
			send:     make(chan []byte, 256),
		}
		
		log.Printf("[WebSocket] Registering client with hub...")
		h.hub.register <- client
		
		// Send welcome message
		welcome := map[string]interface{}{
			"type": "connected",
			"message": "Connected to Chat E2EE",
			"timestamp": time.Now().Unix(),
			"user_id": userID,
			"device_id": deviceID,
		}
		
		welcomeData, err := json.Marshal(welcome)
		if err == nil {
			log.Printf("[WebSocket] Sending welcome message...")
			if err := conn.WriteMessage(websocket.TextMessage, welcomeData); err != nil {
				log.Printf("[WebSocket] ERROR sending welcome: %v", err)
			}
		}
		
		// Create done channel
		done := make(chan struct{})
		
		// Start write pump
		go func() {
			ticker := time.NewTicker(54 * time.Second)
			defer func() {
				ticker.Stop()
				conn.Close()
				close(done)
			}()
			
			for {
				select {
				case message, ok := <-client.send:
					conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
					
					if !ok {
						log.Printf("[WebSocket] Send channel closed")
						conn.WriteMessage(websocket.CloseMessage, []byte{})
						return
					}
					
					log.Printf("[WebSocket] Sending message to client: %d bytes", len(message))
					if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
						log.Printf("[WebSocket] ERROR writing message: %v", err)
						return
					}
					
				case <-ticker.C:
					conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
					if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
						log.Printf("[WebSocket] ERROR sending ping: %v", err)
						return
					}
					log.Printf("[WebSocket] Ping sent")
				}
			}
		}()
		
		// Read pump (blocking)
		conn.SetReadLimit(512 * 1024)
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		conn.SetPongHandler(func(string) error {
			log.Printf("[WebSocket] Pong received")
			conn.SetReadDeadline(time.Now().Add(60 * time.Second))
			return nil
		})
		
		log.Printf("[WebSocket] Starting read loop...")
		
		for {
			messageType, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("[WebSocket] Unexpected close error: %v", err)
				} else {
					log.Printf("[WebSocket] Connection closed: %v", err)
				}
				break
			}
			
			if messageType == websocket.TextMessage {
				log.Printf("[WebSocket] Received from %s: %s", userID, string(message))
				
				// Parse message
				var msg ClientMessage
				if err := json.Unmarshal(message, &msg); err != nil {
					log.Printf("[WebSocket] Parse error: %v", err)
					
					// Send error response
					errResp := map[string]interface{}{
						"type": "error",
						"error": "Invalid message format",
					}
					if data, err := json.Marshal(errResp); err == nil {
						client.send <- data
					}
					continue
				}
				
				// Handle different message types
				switch msg.Type {
				case "ping":
					log.Printf("[WebSocket] Handling ping")
					pong := map[string]interface{}{
						"type": "pong",
						"timestamp": time.Now().Unix(),
					}
					if data, err := json.Marshal(pong); err == nil {
						client.send <- data
					}
					
				case "message":
					log.Printf("[WebSocket] Handling message to %s", msg.To)
					// Relay message to recipient
					if msg.To != "" {
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
		
		// Cleanup
		log.Printf("[WebSocket] Cleaning up connection for %s", userID)
		h.hub.unregister <- client
		<-done
		close(client.send)
		
		log.Printf("[WebSocket] Connection handler ended for %s", userID)
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

func CreateRelayService(redisClient *redis.Client, jwtService *auth.JWTService) (*Handler, *Hub) {
	log.Printf("[WebSocket] Creating relay service...")
	
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
	
	log.Printf("[WebSocket] Relay service created successfully")
	return handler, hub
}
ENDOFFILE

# 4. Reemplazar el websocket.go actual
echo -e "\n4. Reemplazando websocket.go con versión con debug..."
cp src/internal/relay/websocket.go src/internal/relay/websocket.go.bak4
mv src/internal/relay/websocket_debug.go src/internal/relay/websocket.go

# 5. Agregar el test endpoint manualmente si no existe
echo -e "\n5. Agregando test endpoint a main.go..."
# Buscar la línea donde debería ir (antes de app.Listen)
if ! grep -q "test-ws" src/cmd/server/main.go; then
    # Agregar justo después de los otros endpoints pero antes de app.Listen
    sed -i '/go func() {/i\
	// Test WebSocket endpoint (sin autenticación)\
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

# 6. Verificar que el import esté correcto
echo -e "\n6. Verificando imports..."
if ! grep -q '"github.com/gofiber/websocket/v2"' src/cmd/server/main.go; then
    echo "Agregando import de websocket..."
    sed -i '/import (/a\\t"github.com/gofiber/websocket/v2"' src/cmd/server/main.go
fi

# 7. Rebuild
echo -e "\n7. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar"
    cd ..
    exit 1
fi

docker-compose restart backend
cd ..

echo -e "\n8. Esperando que inicie..."
sleep 5

echo -e "\n✅ Fix aplicado con más debug!"
echo ""
echo "Ahora prueba nuevamente y observa los logs detallados:"
echo ""
echo "Terminal 1 - Ver logs detallados:"
echo "./scripts/logs.sh backend -f"
echo ""
echo "Terminal 2 - Probar test endpoint:"
echo "wscat -c 'ws://localhost:8080/test-ws'"
echo ""
echo "Terminal 3 - Probar con auth:"
echo "source /tmp/chat-e2ee-tokens.txt"
echo "wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "Los logs ahora mostrarán exactamente dónde está fallando."