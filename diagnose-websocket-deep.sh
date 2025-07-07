#!/bin/bash

echo "🔍 Diagnóstico profundo del problema de WebSocket"

# 1. Verificar la versión de gofiber/websocket
echo -e "\n1. Verificando versión de gofiber/websocket..."
grep -A 5 "gofiber/websocket" src/go.mod

# 2. Ver cómo se está usando actualmente
echo -e "\n2. Verificando imports y uso actual..."
grep -n "websocket\." src/internal/relay/*.go | head -20

# 3. Crear un test mínimo de WebSocket
echo -e "\n3. Creando handler de test mínimo..."
cat > /tmp/websocket_test_handler.go << 'ENDOFFILE'
// Agregar esto temporalmente a main.go para probar

// Test WebSocket endpoint - agregar después de las rutas normales
app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {
	log.Println("[TEST-WS] Handler started")
	defer log.Println("[TEST-WS] Handler ended")
	
	// Enviar mensaje de bienvenida
	c.WriteMessage(websocket.TextMessage, []byte("Welcome to test WebSocket"))
	
	// Loop de lectura
	for {
		mt, msg, err := c.ReadMessage()
		if err != nil {
			log.Printf("[TEST-WS] Read error: %v", err)
			break
		}
		
		log.Printf("[TEST-WS] Received: %s", string(msg))
		
		// Echo back
		if err := c.WriteMessage(mt, msg); err != nil {
			log.Printf("[TEST-WS] Write error: %v", err)
			break
		}
	}
}))
ENDOFFILE

# 4. Verificar si el problema es con el middleware de autenticación
echo -e "\n4. Verificando el UpgradeHandler..."
grep -A 30 "func (h \*Handler) UpgradeHandler" src/internal/relay/websocket.go

# 5. Crear una versión simplificada sin el Client struct
cat > /tmp/simple_websocket.go << 'ENDOFFILE'
// Versión simplificada para probar si el problema es con el Client struct

func (h *Handler) WebSocketHandlerSimple() fiber.Handler {
	return websocket.New(func(c *websocket.Conn) {
		log.Printf("[SIMPLE] WebSocket connection established")
		
		userID := c.Locals("userID").(string)
		deviceID := c.Locals("deviceID").(string)
		
		log.Printf("[SIMPLE] UserID: %s, DeviceID: %s", userID, deviceID)
		
		// Enviar mensaje de bienvenida
		welcome := map[string]string{
			"type": "welcome",
			"message": "Connected to Chat E2EE WebSocket",
		}
		if data, err := json.Marshal(welcome); err == nil {
			c.WriteMessage(websocket.TextMessage, data)
		}
		
		// Simple read loop
		for {
			messageType, p, err := c.ReadMessage()
			if err != nil {
				log.Printf("[SIMPLE] Read error: %v", err)
				return
			}
			
			log.Printf("[SIMPLE] Received message: %s", string(p))
			
			// Simple echo
			response := map[string]interface{}{
				"type": "echo",
				"data": string(p),
				"timestamp": time.Now().Unix(),
			}
			
			if data, err := json.Marshal(response); err == nil {
				if err := c.WriteMessage(messageType, data); err != nil {
					log.Printf("[SIMPLE] Write error: %v", err)
					return
				}
			}
		}
	})
}
ENDOFFILE

# 6. Sugerir cambios para probar
echo -e "\n5. Sugerencias de debug:"
echo "===================================="
echo ""
echo "OPCIÓN 1: Agregar endpoint de test en main.go"
echo "Agrega esto después de las rutas API en main.go:"
echo ""
cat << 'EOF'
	// Test WebSocket endpoint
	app.Get("/test-ws", websocket.New(func(c *websocket.Conn) {
		log.Println("[TEST-WS] Handler started")
		defer log.Println("[TEST-WS] Handler ended")
		
		// Loop simple
		for {
			mt, msg, err := c.ReadMessage()
			if err != nil {
				log.Printf("[TEST-WS] Error: %v", err)
				break
			}
			log.Printf("[TEST-WS] Received: %s", string(msg))
			c.WriteMessage(mt, append([]byte("Echo: "), msg...))
		}
	}))
EOF

echo ""
echo "Luego prueba con: wscat -c 'ws://localhost:8080/test-ws'"
echo ""
echo "===================================="
echo ""
echo "OPCIÓN 2: Verificar si es un problema de importación"
echo "Revisa que estés usando:"
echo "  github.com/gofiber/websocket/v2"
echo "Y NO:"
echo "  github.com/gofiber/fiber/v2/middleware/websocket"
echo ""
echo "===================================="
echo ""
echo "OPCIÓN 3: Probar con una versión anterior de gofiber/websocket"
echo "En go.mod, cambia la versión a:"
echo "  github.com/gofiber/websocket/v2 v2.1.4"
echo ""
echo "===================================="