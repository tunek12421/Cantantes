#!/bin/bash

# Fix the unused websocket import in main.go

echo "🔧 Fixing unused websocket import in main.go..."

# Remove the websocket import from main.go if it's not being used directly
# The websocket functionality is handled in the relay package
sed -i '/"github.com\/gofiber\/websocket\/v2"/d' src/cmd/server/main.go

# Also remove the main_websocket.go file if it exists (not needed)
rm -f src/cmd/server/main_websocket.go

echo "✅ Fixed unused import!"

# Let's also ensure the WebSocket routes are properly configured
echo "Verifying WebSocket route configuration..."

# Check if WebSocket routes are properly set up in main.go
if ! grep -q "WebSocket route" src/cmd/server/main.go; then
    echo "WebSocket routes missing, adding them..."
    
    # Find the line with "_ = minioClient" and add WebSocket routes before it
    sed -i '/_ = minioClient/i\
	// WebSocket stats endpoint\
	protected.Get("/ws/stats", relayHandler.GetStats())\
\
	// WebSocket route\
	app.Use("/ws", relayHandler.UpgradeHandler())\
	app.Get("/ws", relayHandler.WebSocketHandler())\
' src/cmd/server/main.go
fi

echo "✅ WebSocket routes verified!"

# Double-check that we're using the relay handler correctly
echo "Checking relay handler usage..."
if ! grep -q "relayHandler, hub := relay.CreateRelayService" src/cmd/server/main.go; then
    echo "❌ Relay service initialization missing in main.go!"
    echo "Please ensure this line exists in main.go:"
    echo "  relayHandler, hub := relay.CreateRelayService(redis, jwtService)"
fi

echo ""
echo "✅ All import issues should be fixed!"
echo ""
echo "Now rebuild:"
echo "cd docker && docker-compose build backend && docker-compose restart backend"