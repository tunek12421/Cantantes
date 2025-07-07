#!/bin/bash

echo "🔍 Debugging WebSocket disconnect issue..."

# 1. Primero, verificar que el hub está corriendo
echo -e "\n1. Verificando que el hub está activo..."
curl -s http://localhost:8080/debug/phase3 | jq '.'

# 2. Agregar más logging al inicio del client
cat > /tmp/client_start_fix.go << 'ENDOFFILE'
func (c *Client) Start() {
	log.Printf("[DEBUG] Client.Start() called for UserID=%s, DeviceID=%s", c.UserID, c.DeviceID)
	
	// Registrar el cliente ANTES de iniciar las goroutines
	c.hub.register <- c
	log.Printf("[DEBUG] Client sent to hub.register channel")
	
	// Pequeña pausa para asegurar que el registro se procese
	time.Sleep(100 * time.Millisecond)
	
	// Iniciar goroutines
	go c.writePump()
	log.Printf("[DEBUG] writePump goroutine started")
	
	go c.readPump()
	log.Printf("[DEBUG] readPump goroutine started")
}
ENDOFFILE

# 3. Agregar verificación de panic recovery
cat > /tmp/panic_recovery.go << 'ENDOFFILE'
func (c *Client) readPump() {
	log.Printf("[DEBUG] readPump started for UserID=%s", c.UserID)
	
	// Recover from panics
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[PANIC] readPump panic for UserID=%s: %v", c.UserID, r)
		}
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
		if err := c.conn.SetReadDeadline(time.Now().Add(pongWait)); err != nil {
			log.Printf("[ERROR] Failed to update read deadline: %v", err)
			return err
		}
		c.updateLastActive()
		return nil
	})

	log.Printf("[DEBUG] WebSocket configured, entering read loop for UserID=%s", c.UserID)

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
			log.Printf("[DEBUG] Ignoring non-text message type %d", messageType)
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
	
	// Recover from panics
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[PANIC] writePump panic for UserID=%s: %v", c.UserID, r)
		}
		log.Printf("[DEBUG] writePump ending for UserID=%s", c.UserID)
		ticker.Stop()
		c.conn.Close()
	}()

	// Send initial ping to test connection
	log.Printf("[DEBUG] Sending initial ping to UserID=%s", c.UserID)
	if err := c.conn.SetWriteDeadline(time.Now().Add(writeWait)); err != nil {
		log.Printf("[ERROR] Failed to set initial write deadline: %v", err)
		return
	}
	if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
		log.Printf("[ERROR] Failed to send initial ping: %v", err)
		return
	}

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
ENDOFFILE

# 4. Aplicar los cambios
echo -e "\n2. Aplicando fixes al código..."

# Buscar la función Start en client.go y reemplazarla
sed -i '/func (c \*Client) Start()/,/^}/c\
func (c *Client) Start() {\
	log.Printf("[DEBUG] Client.Start() called for UserID=%s, DeviceID=%s", c.UserID, c.DeviceID)\
	\
	// Registrar el cliente ANTES de iniciar las goroutines\
	c.hub.register <- c\
	log.Printf("[DEBUG] Client sent to hub.register channel")\
	\
	// Pequeña pausa para asegurar que el registro se procese\
	time.Sleep(100 * time.Millisecond)\
	\
	// Iniciar goroutines\
	go c.writePump()\
	log.Printf("[DEBUG] writePump goroutine started")\
	\
	go c.readPump()\
	log.Printf("[DEBUG] readPump goroutine started")\
}' src/internal/relay/client.go

# 5. Rebuild
echo -e "\n3. Rebuilding backend..."
cd docker
docker-compose build backend
docker-compose restart backend
cd ..

echo -e "\n4. Esperando que inicie..."
sleep 3

echo -e "\n✅ Debugging mejorado aplicado!"
echo ""
echo "Ahora ejecuta estos comandos en terminales separadas:"
echo ""
echo "Terminal 1 - Ver logs detallados:"
echo "./scripts/logs.sh backend -f"
echo ""
echo "Terminal 2 - Obtener token fresco:"
echo "chmod +x get-fresh-token.sh && ./get-fresh-token.sh"
echo ""
echo "Terminal 3 - Conectar con el token fresco:"
echo "source /tmp/fresh-token.txt && wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""