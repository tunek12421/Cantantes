#!/bin/bash

# Diagnose why WebSocket routes aren't being registered

echo "🔍 Diagnosing WebSocket registration issue..."

# 1. Check if CreateRelayService exists and is being called
echo -e "\n1. Checking CreateRelayService function..."
grep -n "CreateRelayService" src/internal/relay/websocket.go | head -5
grep -n "CreateRelayService" src/cmd/server/main.go | head -5

# 2. Check if the relay handler is nil
echo -e "\n2. Adding debug logging to main.go..."
# Add debug logging after CreateRelayService
sed -i '/relayHandler, hub := relay.CreateRelayService/a\
	log.Printf("DEBUG: relayHandler is nil: %v, hub is nil: %v", relayHandler == nil, hub == nil)' src/cmd/server/main.go

# 3. Check what WebSocketHandler returns
echo -e "\n3. Checking WebSocketHandler implementation..."
grep -A 10 "func.*WebSocketHandler" src/internal/relay/websocket.go

# 4. Let's add a simple debug endpoint to verify routes are being added
echo -e "\n4. Adding debug endpoint to verify routing..."
sed -i '/WebSocket route/i\
	// Debug endpoint to verify routes are being added\
	app.Get("/debug/test", func(c *fiber.Ctx) error {\
		return c.JSON(fiber.Map{"message": "Debug endpoint working"})\
	})' src/cmd/server/main.go

# 5. Add more debug logging
echo -e "\n5. Adding more debug logging..."
sed -i '/WebSocket stats endpoint/i\
	log.Println("DEBUG: Adding WebSocket routes...")' src/cmd/server/main.go

sed -i '/app.Get("\/ws", relayHandler.WebSocketHandler())/a\
	log.Println("DEBUG: WebSocket routes added")' src/cmd/server/main.go

# 6. Ensure the log for WebSocket endpoint is AFTER route registration
sed -i '/log.Printf("WebSocket endpoint:/d' src/cmd/server/main.go
sed -i '/log.Printf("Debug mode:/a\
		log.Printf("WebSocket endpoint available at: ws://localhost%s/ws", addr)' src/cmd/server/main.go

echo -e "\n✅ Debug logging added!"
echo ""
echo "Now rebuild and check the logs for DEBUG messages:"
echo "cd docker && docker-compose build backend && docker-compose restart backend"
echo ""
echo "Look for:"
echo "- 'DEBUG: relayHandler is nil: false, hub is nil: false'"
echo "- 'DEBUG: Adding WebSocket routes...'"
echo "- 'DEBUG: WebSocket routes added'"
echo ""
echo "Also test the debug endpoint:"
echo "curl http://localhost:8080/debug/test"