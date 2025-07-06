package presence

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Tracker struct {
	redis *redis.Client
}

func NewTracker(redisClient *redis.Client) *Tracker {
	return &Tracker{
		redis: redisClient,
	}
}

func (t *Tracker) SetUserOnline(ctx context.Context, userID, deviceID string) error {
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
	return err
}

func (t *Tracker) SetUserOffline(ctx context.Context, userID string) error {
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
	return err
}

func (t *Tracker) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	return t.redis.SIsMember(ctx, "presence:online_users", userID).Result()
}

func (t *Tracker) GetUserStatus(ctx context.Context, userID string) (map[string]string, error) {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HGetAll(ctx, userKey).Result()
}

func (t *Tracker) GetOnlineUsers(ctx context.Context) ([]string, error) {
	return t.redis.SMembers(ctx, "presence:online_users").Result()
}

func (t *Tracker) UpdatePresence(ctx context.Context, userID, status string) error {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HSet(ctx, userKey, "status", status).Err()
}

func (t *Tracker) StorePendingMessage(ctx context.Context, userID string, message interface{}) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}

	key := fmt.Sprintf("pending:messages:%s", userID)
	pipe := t.redis.Pipeline()
	
	pipe.LPush(ctx, key, data)
	pipe.LTrim(ctx, key, 0, 99)
	pipe.Expire(ctx, key, 7*24*time.Hour)

	_, err = pipe.Exec(ctx)
	return err
}

func (t *Tracker) GetPendingMessages(ctx context.Context, userID string) ([]string, error) {
	key := fmt.Sprintf("pending:messages:%s", userID)
	messages, err := t.redis.LRange(ctx, key, 0, -1).Result()
	if err != nil {
		return nil, err
	}
	
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}
	
	return messages, nil
}

func (t *Tracker) ClearPendingMessages(ctx context.Context, userID string) error {
	key := fmt.Sprintf("pending:messages:%s", userID)
	return t.redis.Del(ctx, key).Err()
}

func (t *Tracker) StoreMessageMetadata(ctx context.Context, messageID, from, to string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	data := map[string]interface{}{
		"from":      from,
		"to":        to,
		"timestamp": time.Now().Unix(),
		"delivered": false,
		"read":      false,
	}

	pipe := t.redis.Pipeline()
	pipe.HSet(ctx, key, data)
	pipe.Expire(ctx, key, 24*time.Hour)

	_, err := pipe.Exec(ctx)
	return err
}

func (t *Tracker) MarkMessageDelivered(ctx context.Context, messageID string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	return t.redis.HSet(ctx, key, map[string]interface{}{
		"delivered":    true,
		"delivered_at": time.Now().Unix(),
	}).Err()
}

func (t *Tracker) MarkMessageRead(ctx context.Context, messageID string) error {
	key := fmt.Sprintf("message:meta:%s", messageID)
	return t.redis.HSet(ctx, key, map[string]interface{}{
		"read":    true,
		"read_at": time.Now().Unix(),
	}).Err()
}

func (t *Tracker) GetActiveDevices(ctx context.Context, userID string) ([]string, error) {
	deviceKey := fmt.Sprintf("presence:devices:%s", userID)
	return t.redis.SMembers(ctx, deviceKey).Result()
}

func (t *Tracker) Heartbeat(ctx context.Context, userID string) error {
	userKey := fmt.Sprintf("presence:user:%s", userID)
	return t.redis.HSet(ctx, userKey, "last_seen", time.Now().Unix()).Err()
}

func (t *Tracker) CleanupInactive(ctx context.Context, inactiveThreshold time.Duration) error {
	onlineUsers, err := t.GetOnlineUsers(ctx)
	if err != nil {
		return err
	}

	now := time.Now().Unix()
	threshold := now - int64(inactiveThreshold.Seconds())

	for _, userID := range onlineUsers {
		status, err := t.GetUserStatus(ctx, userID)
		if err != nil {
			continue
		}

		if lastSeenStr, ok := status["last_seen"]; ok {
			var lastSeen int64
			fmt.Sscanf(lastSeenStr, "%d", &lastSeen)
			
			if lastSeen < threshold {
				t.SetUserOffline(ctx, userID)
			}
		}
	}

	return nil
}
