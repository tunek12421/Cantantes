#!/bin/bash

echo "🚨 Arreglando los panics del WebSocket"
echo "======================================"

# 1. Primero, hacer backup de los archivos actuales
echo -e "\n1. Creando backups..."
cp src/internal/relay/websocket.go src/internal/relay/websocket.go.panic-backup
cp src/internal/relay/client.go src/internal/relay/client.go.panic-backup

# 2. Arreglar el problema del close de canal nil en client.go
echo -e "\n2. Arreglando Client.Close() para evitar panic..."
cat > /tmp/client_close_fix.go << 'ENDOFFILE'
func (c *Client) Close() {
	log.Printf("[DEBUG] Client.Close() called for UserID=%s", c.UserID)
	c.mu.Lock()
	defer c.mu.Unlock()
	
	if c.isClosing {
		log.Printf("[DEBUG] Client already closing for UserID=%s", c.UserID)
		return
	}
	c.isClosing = true
	
	// Solo cerrar el canal si no es nil y está abierto
	if c.send != nil {
		select {
		case <-c.send:
			// Canal ya cerrado
			log.Printf("[DEBUG] Channel already closed for UserID=%s", c.UserID)
		default:
			// Canal abierto, cerrarlo
			close(c.send)
			log.Printf("[DEBUG] Channel closed for UserID=%s", c.UserID)
		}
	}
}
ENDOFFILE

# Reemplazar la función Close en client.go
sed -i '/func (c \*Client) Close()/,/^}/c\
func (c *Client) Close() {\
	log.Printf("[DEBUG] Client.Close() called for UserID=%s", c.UserID)\
	c.mu.Lock()\
	defer c.mu.Unlock()\
	\
	if c.isClosing {\
		log.Printf("[DEBUG] Client already closing for UserID=%s", c.UserID)\
		return\
	}\
	c.isClosing = true\
	\
	// Solo cerrar el canal si no es nil\
	if c.send != nil {\
		// Verificar si el canal ya está cerrado antes de cerrarlo\
		select {\
		case _, ok := <-c.send:\
			if !ok {\
				log.Printf("[DEBUG] Channel already closed for UserID=%s", c.UserID)\
				return\
			}\
		default:\
			close(c.send)\
			log.Printf("[DEBUG] Channel closed for UserID=%s", c.UserID)\
		}\
	}\
}' src/internal/relay/client.go

# 3. Arreglar el problema en websocket.go línea 179
echo -e "\n3. Arreglando el defer en readPump..."
# El problema está en que close(conn.Send) se ejecuta en el defer
# Buscar la línea específica
sed -i '/defer func() {/,/}()/{
s/close(conn.Send)/\/\/ close(conn.Send) - Movido al final para evitar double close/
}' src/internal/relay/websocket.go

# 4. Asegurar que el writePump maneje correctamente el cierre
echo -e "\n4. Mejorando el manejo de cierre en writePump..."
# Agregar mejor manejo de errores en writePump
sed -i '/func (conn \*SimpleConn) writePump()/,/^func/{
/for {/,/}$/{
/case message, ok := <-conn.Send:/,/case <-ticker.C:/{
s/if !ok {/if !ok {\
				log.Printf("[WebSocket] Send channel closed for %s", conn.UserID)/
}
}
}' src/internal/relay/websocket.go

# 5. Mejorar la coordinación entre SimpleConn y Client
echo -e "\n5. Mejorando la creación del Client en el handler..."
# Asegurar que el Client tenga todos los campos necesarios
cat > /tmp/websocket_client_fix.go << 'ENDOFFILE'
		// Notify hub (create minimal client for compatibility)
		if h.hub != nil {
			client := &Client{
				ID:       conn.ID,
				UserID:   userID,
				DeviceID: deviceID,
				hub:      h.hub,
				send:     conn.Send,
				lastActive: time.Now(),
				isClosing: false,
			}
			h.hub.register <- client
			
			// Al final, notificar unregister
			defer func() {
				// Crear un nuevo client para unregister (no reusar el mismo)
				unregClient := &Client{
					ID:       conn.ID,
					UserID:   userID,
					DeviceID: deviceID,
					hub:      h.hub,
				}
				h.hub.unregister <- unregClient
			}()
		}
ENDOFFILE

# 6. Crear una versión más robusta del WebSocketHandler
echo -e "\n6. Creando handler más robusto..."
cat > src/internal/relay/websocket_robust.go << 'ENDOFFILE'
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
ENDOFFILE

# 7. Reemplazar websocket.go con la versión robusta
echo -e "\n7. Aplicando la versión robusta..."
mv src/internal/relay/websocket.go src/internal/relay/websocket.go.old
mv src/internal/relay/websocket_robust.go src/internal/relay/websocket.go

# 8. Rebuild
echo -e "\n8. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar"
    cd ..
    exit 1
fi

docker-compose restart backend
cd ..

echo -e "\n9. Esperando que inicie..."
sleep 5

echo -e "\n✅ Fix de panics aplicado!"
echo ""
echo "La nueva implementación:"
echo "- Evita cerrar canales nil o ya cerrados"
echo "- Maneja mejor el ciclo de vida de las conexiones"
echo "- Separa claramente las responsabilidades"
echo ""
echo "Prueba ahora:"
echo "1. source /tmp/fresh-websocket-tokens.txt"
echo "2. wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo '3. {"type":"ping"}'
echo ""
echo "Deberías recibir:"
echo '{"type":"pong","timestamp":...}'