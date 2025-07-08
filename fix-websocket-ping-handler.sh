#!/bin/bash

echo "🔧 Arreglando el handler de ping en WebSocket"
echo "============================================"

# 1. Ver los logs completos del error
echo -e "\n1. Buscando el error completo en los logs..."
docker logs chat_backend --tail 100 | grep -A 10 -B 5 "panic\|runtime error\|fatal" | head -30

# 2. El problema está en que el case "ping" está tratando de escribir al canal pero algo falla
# Vamos a arreglar el handler
echo -e "\n2. Arreglando el handler de mensajes..."

# Buscar la línea específica del case "ping" en websocket.go
echo "Verificando el handler actual de ping:"
grep -A 10 'case "ping":' src/internal/relay/websocket.go

# 3. Crear un parche para el handler
cat > /tmp/websocket_ping_fix.go << 'ENDOFFILE'
			// Handle message types
			switch msg.Type {
			case "ping":
				log.Printf("[WebSocket] Handling ping from %s", conn.UserID)
				pong := map[string]interface{}{
					"type": "pong",
					"timestamp": time.Now().Unix(),
				}
				if data, err := json.Marshal(pong); err == nil {
					select {
					case conn.Send <- data:
						log.Printf("[WebSocket] Pong queued for %s", conn.UserID)
					default:
						log.Printf("[WebSocket] Send buffer full for %s", conn.UserID)
					}
				}
ENDOFFILE

# 4. Aplicar el fix - reemplazar el case "ping" completo
echo -e "\n3. Aplicando el fix..."
# Este es un fix temporal, vamos a agregar más logging para debug
sed -i '/case "ping":/,/case "message":/{
/case "ping":/!{
/case "message":/!d
}
}' src/internal/relay/websocket.go

# Insertar el nuevo handler
sed -i '/case "ping":/a\
				log.Printf("[WebSocket] Handling ping from %s", conn.UserID)\
				pong := map[string]interface{}{\
					"type": "pong",\
					"timestamp": time.Now().Unix(),\
				}\
				if data, err := json.Marshal(pong); err == nil {\
					select {\
					case conn.Send <- data:\
						log.Printf("[WebSocket] Pong queued for %s", conn.UserID)\
					default:\
						log.Printf("[WebSocket] Send buffer full for %s", conn.UserID)\
					}\
				}' src/internal/relay/websocket.go

# 5. También verificar que el readPump no esté cerrando el canal prematuramente
echo -e "\n4. Verificando la función readPump..."
grep -A 20 "func (conn \*SimpleConn) readPump" src/internal/relay/websocket.go | grep -E "close|Send"

# 6. Agregar un defer recover para capturar panics
echo -e "\n5. Agregando recover para capturar panics..."
# Buscar el inicio de readPump y agregar recover
sed -i '/func (conn \*SimpleConn) readPump/,/^{/{
/defer func() {/!{
/^{/a\
	defer func() {\
		if r := recover(); r != nil {\
			log.Printf("[WebSocket] PANIC in readPump: %v", r)\
		}\
	}()
}
}' src/internal/relay/websocket.go

# 7. Rebuild
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

echo -e "\n✅ Fix aplicado!"
echo ""
echo "Ahora prueba nuevamente:"
echo ""
echo "1. Ver logs en tiempo real:"
echo "   docker logs chat_backend -f --tail 50"
echo ""
echo "2. En otra terminal, conectar:"
echo "   source /tmp/fresh-websocket-tokens.txt"
echo "   wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
echo ""
echo "3. Enviar ping:"
echo '   {"type":"ping"}'
echo ""
echo "Si sigue fallando, buscaremos el stack trace completo del panic."