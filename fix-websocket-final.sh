#!/bin/bash

echo "🚀 Fix FINAL para WebSocket - Reescribiendo todo"
echo "==============================================="

# 1. Primero, verificar qué está pasando con el test endpoint
echo -e "\n1. Debug del test endpoint..."
echo "Verificando que el endpoint esté registrado:"
grep -B5 -A5 "test-ws" src/cmd/server/main.go | head -20

# 2. El problema es que el handler está usando el client.go antiguo
# Vamos a crear una versión que NO use client.go en absoluto
echo -e "\n2. Creando websocket handler completamente nuevo..."
cat > src/internal/relay/websocket_working.go << 'ENDOFFILE'
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

// SimpleConn wraps websocket connection with user info
type SimpleConn struct {
	ID       string
	UserID   string
	DeviceID string
	Conn     *websocket.Conn
	Send     chan []byte
	Hub      *Hub
}

type Handler struct {
	hub        *Hub
	jwtService *auth.JWTService
	
	// Temporary connection tracking
	connMu sync.RWMutex
	conns  map[string]*SimpleConn
}

func NewHandler(hub *Hub, jwtService *auth.JWTService) *Handler {
	return &Handler{
		hub:        hub,
		jwtService: jwtService,
		conns:      make(map[string]*SimpleConn),
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
	return websocket.New(func(ws *websocket.Conn) {
		// Get user info
		userID := ws.Locals("userID").(string)
		deviceID := ws.Locals("deviceID").(string)
		
		log.Printf("[WebSocket] New connection: UserID=%s, DeviceID=%s", userID, deviceID)
		
		// Create simple connection wrapper
		conn := &SimpleConn{
			ID:       uuid.New().String(),
			UserID:   userID,
			DeviceID: deviceID,
			Conn:     ws,
			Send:     make(chan []byte, 256),
			Hub:      h.hub,
		}
		
		// Register connection
		h.connMu.Lock()
		h.conns[conn.ID] = conn
		h.connMu.Unlock()
		
		// Notify hub (create minimal client for compatibility)
		if h.hub != nil {
			client := &Client{
				ID:       conn.ID,
				UserID:   userID,
				DeviceID: deviceID,
				hub:      h.hub,
				send:     conn.Send,
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
		
		// Start goroutines
		go conn.writePump()
		go conn.readPump(h)
		
		// Block until connection closes
		<-conn.Send // Will be closed when readPump exits
		
		// Cleanup
		h.connMu.Lock()
		delete(h.conns, conn.ID)
		h.connMu.Unlock()
		
		// Notify hub
		if h.hub != nil {
			client := &Client{
				ID:       conn.ID,
				UserID:   userID,
				DeviceID: deviceID,
				hub:      h.hub,
			}
			h.hub.unregister <- client
		}
		
		log.Printf("[WebSocket] Connection closed: UserID=%s", userID)
	})
}

func (conn *SimpleConn) readPump(h *Handler) {
	defer func() {
		conn.Conn.Close()
		close(conn.Send)
	}()
	
	conn.Conn.SetReadLimit(512 * 1024)
	conn.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	conn.Conn.SetPongHandler(func(string) error {
		log.Printf("[WebSocket] Pong received from %s", conn.UserID)
		conn.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	
	for {
		messageType, message, err := conn.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WebSocket] Error: %v", err)
			}
			break
		}
		
		if messageType == websocket.TextMessage {
			log.Printf("[WebSocket] Received from %s: %s", conn.UserID, string(message))
			
			// Parse message
			var msg ClientMessage
			if err := json.Unmarshal(message, &msg); err != nil {
				log.Printf("[WebSocket] Parse error: %v", err)
				continue
			}
			
			// Handle message types
			switch msg.Type {
			case "ping":
				pong := map[string]interface{}{
					"type": "pong",
					"timestamp": time.Now().Unix(),
				}
				if data, err := json.Marshal(pong); err == nil {
					conn.Send <- data
				}
				
			case "message":
				if msg.To != "" && h.hub != nil {
					relayMsg := &RelayMessage{
						From:     conn.UserID,
						To:       msg.To,
						DeviceID: conn.DeviceID,
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

func (conn *SimpleConn) writePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		conn.Conn.Close()
	}()
	
	for {
		select {
		case message, ok := <-conn.Send:
			conn.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			
			if !ok {
				conn.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			
			if err := conn.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			
		case <-ticker.C:
			conn.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
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

# 3. Reemplazar websocket.go
echo -e "\n3. Reemplazando websocket.go..."
cp src/internal/relay/websocket.go src/internal/relay/websocket.go.bak5
mv src/internal/relay/websocket_working.go src/internal/relay/websocket.go

# 4. Arreglar el problema del test endpoint - parece que no se está registrando correctamente
echo -e "\n4. Verificando dónde está el test endpoint en main.go..."
# Buscar exactamente dónde está y si está antes de app.Listen
line_num=$(grep -n "test-ws" src/cmd/server/main.go | head -1 | cut -d: -f1)
echo "Test endpoint está en línea: $line_num"

# Verificar si está antes de la goroutine
grep -n "go func()" src/cmd/server/main.go | head -1

# 5. Mover el test endpoint ANTES de iniciar el servidor
echo -e "\n5. Reorganizando endpoints en main.go..."
# Primero, eliminar el test endpoint actual
sed -i '/\/\/ Test WebSocket endpoint/,/log.Println("✅ Test WebSocket endpoint registered at \/test-ws")/d' src/cmd/server/main.go

# Agregar el test endpoint justo después de los otros endpoints API
sed -i '/protected.Get("\/ws\/stats", relayHandler.GetStats())/a\
\
	// Test WebSocket endpoint (sin autenticación)\
	app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {\
		log.Println("[TEST-WS] New connection")\
		c.WriteMessage(websocket.TextMessage, []byte("Welcome to test WebSocket!"))\
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
	log.Println("✅ Registered /test-ws endpoint")' src/cmd/server/main.go

# 6. Rebuild
echo -e "\n6. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar"
    cd ..
    exit 1
fi

docker-compose restart backend
cd ..

echo -e "\n7. Esperando que inicie..."
sleep 5

# 8. Verificar que los endpoints están registrados
echo -e "\n8. Verificando endpoints..."
curl -s http://localhost:8080/health | jq '.status'

echo -e "\n✅ Fix FINAL aplicado!"
echo ""
echo "=== PRUEBAS ==="
echo ""
echo "1. Verificar que el test endpoint funciona:"
echo "   curl -i http://localhost:8080/test-ws"
echo "   (Debería devolver 426 Upgrade Required)"
echo ""
echo "2. Conectar al test endpoint:"
echo "   wscat -c 'ws://localhost:8080/test-ws'"
echo ""
echo "3. Conectar con autenticación:"
echo "   source /tmp/chat-e2ee-tokens.txt"
echo "   wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "4. Enviar un ping cuando estés conectado:"
echo '   {"type":"ping"}'