#!/bin/bash

echo "🔍 Verificando Redis y Presence Tracker..."

# 1. Verificar que Redis está funcionando
echo -e "\n1. Verificando Redis..."
./scripts/shell.sh redis PING

# 2. Ver si hay errores de Redis en los logs
echo -e "\n2. Buscando errores de Redis en logs..."
./scripts/logs.sh backend | grep -i "redis\|presence" | tail -20

# 3. Verificar manualmente las operaciones de Redis
echo -e "\n3. Verificando operaciones de Redis manualmente..."
cat > /tmp/test_redis.sh << 'EOF'
# Test Redis operations
echo "PING"
echo "KEYS presence:*"
echo "KEYS session:*"
EOF

./scripts/shell.sh redis < /tmp/test_redis.sh

# 4. Agregar un check temporal al SetUserOnline
echo -e "\n4. Agregando logging temporal al presence tracker..."

cat > /tmp/presence_debug.go << 'ENDOFFILE'
package presence

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

type Tracker struct {
	redis *redis.Client
}

func NewTracker(redisClient *redis.Client) *Tracker {
	// Verificar que Redis funciona al crear el tracker
	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Printf("[ERROR] Redis not working in presence tracker: %v", err)
	} else {
		log.Printf("[DEBUG] Redis connection OK in presence tracker")
	}
	
	return &Tracker{
		redis: redisClient,
	}
}

func (t *Tracker) SetUserOnline(ctx context.Context, userID, deviceID string) error {
	log.Printf("[DEBUG] SetUserOnline called for userID=%s, deviceID=%s", userID, deviceID)
	
	if t.redis == nil {
		log.Printf("[ERROR] Redis client is nil!")
		return fmt.Errorf("redis client is nil")
	}
	
	pipe := t.redis.Pipeline()

	userKey := fmt.Sprintf("presence:user:%s", userID)
	pipe.HSet(ctx, userKey, map[string]interface{}{
		"status":    "online",
		"last_seen": time.Now().Unix(),
	})
	pipe.Expire(ctx, userKey, 24*time.Hour)

	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	pipe.SAdd(ctx, deviceKey, deviceID)
	pipe.Expire(ctx, deviceKey, 24*time.Hour)

	pipe.SAdd(ctx, "presence:online_users", userID)

	_, err := pipe.Exec(ctx)
	if err != nil {
		log.Printf("[ERROR] Failed to set user online: %v", err)
		return err
	}
	
	log.Printf("[DEBUG] User %s set online successfully", userID)
	return nil
}

func (t *Tracker) SetUserOffline(ctx context.Context, userID string) error {
	log.Printf("[DEBUG] SetUserOffline called for userID=%s", userID)
	
	if t.redis == nil {
		log.Printf("[ERROR] Redis client is nil!")
		return fmt.Errorf("redis client is nil")
	}
	
	pipe := t.redis.Pipeline()

	userKey := fmt.Sprintf("presence:user:%s", userID)
	pipe.HSet(ctx, userKey, map[string]interface{}{
		"status":    "offline",
		"last_seen": time.Now().Unix(),
	})

	pipe.SRem(ctx, "presence:online_users", userID)

	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	pipe.Del(ctx, deviceKey)

	_, err := pipe.Exec(ctx)
	if err != nil {
		log.Printf("[ERROR] Failed to set user offline: %v", err)
		return err
	}
	
	log.Printf("[DEBUG] User %s set offline successfully", userID)
	return nil
}
ENDOFFILE

# Copiar solo las primeras funciones con debug
head -100 /tmp/presence_debug.go > src/internal/presence/tracker_debug.go
tail -n +60 src/internal/presence/tracker.go >> src/internal/presence/tracker_debug.go
mv src/internal/presence/tracker_debug.go src/internal/presence/tracker.go

# 5. Rebuild con el debug de presence
echo -e "\n5. Rebuilding con debug de presence..."
cd docker
docker-compose build backend
docker-compose restart backend
cd ..

sleep 3

echo -e "\n✅ Debug de Redis/Presence agregado!"
echo ""
echo "Ahora intenta conectar nuevamente y verás:"
echo "1. Si Redis está funcionando correctamente"
echo "2. Si el presence tracker está fallando"
echo "3. Logs más detallados del proceso"