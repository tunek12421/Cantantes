#!/bin/bash

echo "🔧 Fix completo para WebSocket - Handler bloqueante"

# 1. Verificar el estado actual del handler
echo -e "\n1. Verificando handler actual..."
echo "=== websocket.go actual ==="
grep -A 30 "func (h \*Handler) WebSocketHandler" src/internal/relay/websocket.go | head -40

# 2. Crear un handler completamente nuevo que bloquee correctamente
cat > /tmp/websocket_handler_fix.go << 'ENDOFFILE'
func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(c *websocket.Conn) {
		log.Printf("[DEBUG] WebSocketHandler called, conn=%p", c)
		
		if c == nil {
			log.Println("[ERROR] WebSocket handler received nil connection")
			return
		}
		
		userID, ok := c.Locals("userID").(string)
		if !ok || userID == "" {
			log.Println("[ERROR] WebSocket: missing userID")
			c.WriteMessage(websocket.CloseMessage, []byte("Missing authentication"))
			c.Close()
			return
		}

		deviceID, ok := c.Locals("deviceID").(string)
		if !ok || deviceID == "" {
			log.Println("[ERROR] WebSocket: missing deviceID")
			c.WriteMessage(websocket.CloseMessage, []byte("Missing device ID"))
			c.Close()
			return
		}

		// Crear el cliente
		client := NewClient(h.hub, c, userID, deviceID)
		if client == nil {
			log.Printf("[ERROR] Failed to create client for UserID=%s", userID)
			c.Close()
			return
		}
		
		log.Printf("[DEBUG] New WebSocket connection: UserID=%s, DeviceID=%s, ClientID=%s, conn=%p",
			userID, deviceID, client.ID, c)

		// Registrar el cliente en el hub
		h.hub.register <- client
		
		// Crear un canal para señalizar cuando terminar
		done := make(chan struct{})
		
		// Iniciar las goroutines con el handler como dueño de la conexión
		go func() {
			defer func() {
				close(done)
				h.hub.unregister <- client
			}()
			client.readPumpWithConn(c)
		}()
		
		go func() {
			client.writePumpWithConn(c)
		}()
		
		// IMPORTANTE: Bloquear hasta que la conexión se cierre
		<-done
		
		log.Printf("[DEBUG] WebSocket handler exiting for UserID=%s", userID)
	}, websocket.Config{
		ReadBufferSize:    4096,
		WriteBufferSize:   4096,
		EnableCompression: false,
	})
}
ENDOFFILE

# 3. Crear una versión alternativa del client que no dependa de c.conn
cat > /tmp/client_alternative.go << 'ENDOFFILE'
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
ENDOFFILE

# 4. Aplicar los cambios

echo -e "\n2. Creando backup de los archivos actuales..."
cp src/internal/relay/websocket.go src/internal/relay/websocket.go.bak
cp src/internal/relay/client.go src/internal/relay/client.go.bak

echo -e "\n3. Reemplazando el WebSocketHandler completamente..."
# Buscar y reemplazar toda la función WebSocketHandler
python3 << 'ENDPYTHON'
import re

# Leer el archivo
with open('src/internal/relay/websocket.go', 'r') as f:
    content = f.read()

# El nuevo handler
new_handler = '''func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(c *websocket.Conn) {
		log.Printf("[DEBUG] WebSocketHandler called, conn=%p", c)
		
		if c == nil {
			log.Println("[ERROR] WebSocket handler received nil connection")
			return
		}
		
		userID, ok := c.Locals("userID").(string)
		if !ok || userID == "" {
			log.Println("[ERROR] WebSocket: missing userID")
			c.WriteMessage(websocket.CloseMessage, []byte("Missing authentication"))
			c.Close()
			return
		}

		deviceID, ok := c.Locals("deviceID").(string)
		if !ok || deviceID == "" {
			log.Println("[ERROR] WebSocket: missing deviceID")
			c.WriteMessage(websocket.CloseMessage, []byte("Missing device ID"))
			c.Close()
			return
		}

		// Crear el cliente
		client := NewClient(h.hub, c, userID, deviceID)
		if client == nil {
			log.Printf("[ERROR] Failed to create client for UserID=%s", userID)
			c.Close()
			return
		}
		
		log.Printf("[DEBUG] New WebSocket connection: UserID=%s, DeviceID=%s, ClientID=%s, conn=%p",
			userID, deviceID, client.ID, c)

		// Registrar el cliente en el hub
		h.hub.register <- client
		
		// Crear un canal para señalizar cuando terminar
		done := make(chan struct{})
		
		// Iniciar las goroutines con el handler como dueño de la conexión
		go func() {
			defer func() {
				close(done)
				h.hub.unregister <- client
			}()
			client.readPumpWithConn(c)
		}()
		
		go func() {
			client.writePumpWithConn(c)
		}()
		
		// IMPORTANTE: Bloquear hasta que la conexión se cierre
		<-done
		
		log.Printf("[DEBUG] WebSocket handler exiting for UserID=%s", userID)
	}, websocket.Config{
		ReadBufferSize:    4096,
		WriteBufferSize:   4096,
		EnableCompression: false,
	})
}'''

# Buscar y reemplazar la función completa
pattern = r'func \(h \*Handler\) WebSocketHandler\(\) fiber\.Handler \{[\s\S]*?\n\}\)'
if re.search(pattern, content):
    content = re.sub(pattern, new_handler, content)
    with open('src/internal/relay/websocket.go', 'w') as f:
        f.write(content)
    print("✅ WebSocketHandler reemplazado exitosamente")
else:
    print("❌ No se encontró el patrón del WebSocketHandler")
ENDPYTHON

# 5. Agregar los métodos alternativos al client.go
echo -e "\n4. Agregando métodos alternativos a client.go..."
cat /tmp/client_alternative.go >> src/internal/relay/client.go

# 6. Rebuild
echo -e "\n5. Rebuilding backend..."
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo "❌ Error al compilar. Verificando errores..."
    docker-compose logs backend | tail -50
    exit 1
fi

docker-compose restart backend
cd ..

echo -e "\n6. Esperando que inicie..."
sleep 5

echo -e "\n✅ Fix completo aplicado!"
echo ""
echo "Ahora verifica los logs y prueba:"
echo ""
echo "Terminal 1:"
echo "./scripts/logs.sh backend -f | grep -E '(DEBUG|ERROR|conn=|WebSocket)'"
echo ""
echo "Terminal 2:"
echo "source /tmp/chat-e2ee-tokens.txt && wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""