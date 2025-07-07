#!/bin/bash

echo "🔧 Arreglando el problema de conexión nil en WebSocket..."

# 1. Primero, verificar el problema actual en websocket.go
echo -e "\n1. Verificando el handler actual..."
grep -A 20 "WebSocketHandler" src/internal/relay/websocket.go | head -30

# 2. Crear fix para el client.go
cat > /tmp/fix_client_nil.go << 'ENDOFFILE'
// En client.go, agregar verificación de nil y mejor manejo

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
	
	// Registrar el cliente
	c.hub.register <- c
	log.Printf("[DEBUG] Client sent to hub.register channel")
	
	// Iniciar goroutines
	go c.writePump()
	log.Printf("[DEBUG] writePump goroutine started")
	
	go c.readPump()
	log.Printf("[DEBUG] readPump goroutine started")
}

func (c *Client) readPump() {
	log.Printf("[DEBUG] readPump started for UserID=%s, conn=%p", c.UserID, c.conn)
	
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[PANIC] readPump panic for UserID=%s: %v", c.UserID, r)
		}
		log.Printf("[DEBUG] readPump ending for UserID=%s", c.UserID)
		c.hub.unregister <- c
		if c.conn != nil {
			c.conn.Close()
		}
	}()

	// Verificar que tenemos una conexión válida
	if c.conn == nil {
		log.Printf("[ERROR] readPump: conn is nil for UserID=%s", c.UserID)
		return
	}

	// Configure WebSocket
	c.conn.SetReadLimit(maxMessageSize)
	if err := c.conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
		log.Printf("[ERROR] Failed to set read deadline: %v (conn=%p)", err, c.conn)
		return
	}
	
	// Continuar con el resto del código...
}
ENDOFFILE

# 3. Arreglar el websocket handler
cat > /tmp/fix_websocket_handler.go << 'ENDOFFILE'
func (h *Handler) WebSocketHandler() fiber.Handler {
	return websocket.New(func(c *websocket.Conn) {
		// Log para debug
		log.Printf("[DEBUG] WebSocketHandler called, conn=%p", c)
		
		// Verificar que tenemos la conexión
		if c == nil {
			log.Println("[ERROR] WebSocket handler received nil connection")
			return
		}
		
		// Obtener userID y deviceID del contexto
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

		// Iniciar el cliente
		client.Start()
		
		// IMPORTANTE: No salir de esta función hasta que la conexión se cierre
		// El websocket handler de Fiber espera que bloqueemos aquí
		select {}
	}, websocket.Config{
		ReadBufferSize:    4096,
		WriteBufferSize:   4096,
		EnableCompression: false,
	})
}
ENDOFFILE

# 4. Aplicar los cambios
echo -e "\n2. Aplicando fixes..."

# Actualizar client.go con verificaciones de nil
sed -i '/func NewClient/,/^}/c\
func NewClient(hub *Hub, conn *websocket.Conn, userID, deviceID string) *Client {\
	if conn == nil {\
		log.Printf("[ERROR] NewClient called with nil connection for UserID=%s", userID)\
		return nil\
	}\
	\
	return &Client{\
		ID:         uuid.New().String(),\
		UserID:     userID,\
		DeviceID:   deviceID,\
		hub:        hub,\
		conn:       conn,\
		send:       make(chan []byte, channelBufferSize),\
		lastActive: time.Now(),\
	}\
}' src/internal/relay/client.go

# Actualizar Start() con verificaciones
sed -i '/func (c \*Client) Start()/,/^}/c\
func (c *Client) Start() {\
	if c == nil || c.conn == nil {\
		log.Printf("[ERROR] Client.Start() called with nil client or connection")\
		return\
	}\
	\
	log.Printf("[DEBUG] Client.Start() called for UserID=%s, DeviceID=%s, conn=%p", c.UserID, c.DeviceID, c.conn)\
	\
	c.hub.register <- c\
	log.Printf("[DEBUG] Client sent to hub.register channel")\
	\
	go c.writePump()\
	log.Printf("[DEBUG] writePump goroutine started")\
	\
	go c.readPump()\
	log.Printf("[DEBUG] readPump goroutine started")\
}' src/internal/relay/client.go

# 5. Actualizar el WebSocket handler para que no salga inmediatamente
echo -e "\n3. Actualizando WebSocket handler..."
sed -i '/func (h \*Handler) WebSocketHandler/,/^}$/c\
func (h *Handler) WebSocketHandler() fiber.Handler {\
	return websocket.New(func(c *websocket.Conn) {\
		log.Printf("[DEBUG] WebSocketHandler called, conn=%p", c)\
		\
		if c == nil {\
			log.Println("[ERROR] WebSocket handler received nil connection")\
			return\
		}\
		\
		userID, ok := c.Locals("userID").(string)\
		if !ok || userID == "" {\
			log.Println("[ERROR] WebSocket: missing userID")\
			c.WriteMessage(websocket.CloseMessage, []byte("Missing authentication"))\
			c.Close()\
			return\
		}\
\
		deviceID, ok := c.Locals("deviceID").(string)\
		if !ok || deviceID == "" {\
			log.Println("[ERROR] WebSocket: missing deviceID")\
			c.WriteMessage(websocket.CloseMessage, []byte("Missing device ID"))\
			c.Close()\
			return\
		}\
\
		client := NewClient(h.hub, c, userID, deviceID)\
		if client == nil {\
			log.Printf("[ERROR] Failed to create client for UserID=%s", userID)\
			c.Close()\
			return\
		}\
		\
		log.Printf("[DEBUG] New WebSocket connection: UserID=%s, DeviceID=%s, ClientID=%s, conn=%p",\
			userID, deviceID, client.ID, c)\
\
		client.Start()\
		\
		// Block until connection closes\
		select {}\
	}, websocket.Config{\
		ReadBufferSize:    4096,\
		WriteBufferSize:   4096,\
		EnableCompression: false,\
	})\
}' src/internal/relay/websocket.go

# 6. Rebuild
echo -e "\n4. Rebuilding backend..."
cd docker
docker-compose build backend
docker-compose restart backend
cd ..

echo -e "\n5. Esperando que inicie..."
sleep 3

echo -e "\n✅ Fix aplicado!"
echo ""
echo "Ahora prueba nuevamente:"
echo "1. source /tmp/chat-e2ee-tokens.txt"
echo "2. wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "También puedes ver los logs en otra terminal:"
echo "./scripts/logs.sh backend -f | grep -E '(DEBUG|ERROR|conn=)'"