package relay

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"chat-e2ee/internal/presence"
)

type RelayMessage struct {
	From     string      `json:"from"`
	To       string      `json:"to"`
	DeviceID string      `json:"device_id"`
	Type     MessageType `json:"type"`
	Payload  string      `json:"payload"`
}

type Hub struct {
	clients    map[string]map[string]*Client
	clientsMu  sync.RWMutex

	relay      chan *RelayMessage
	register   chan *Client
	unregister chan *Client

	presence *presence.Tracker

	stats   *HubStats
	statsMu sync.RWMutex
}

type HubStats struct {
	TotalConnections  int64
	ActiveConnections int
	MessagesRelayed   int64
	LastActivity      time.Time
}

func NewHub(presenceTracker *presence.Tracker) *Hub {
	return &Hub{
		clients:    make(map[string]map[string]*Client),
		relay:      make(chan *RelayMessage, 1000),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		presence:   presenceTracker,
		stats:      &HubStats{},
	}
}

func (h *Hub) Run() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case client := <-h.register:
			h.registerClient(client)

		case client := <-h.unregister:
			h.unregisterClient(client)

		case message := <-h.relay:
			h.relayMessage(message)

		case <-ticker.C:
			h.cleanup()
		}
	}
}

func (h *Hub) registerClient(client *Client) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if _, exists := h.clients[client.UserID]; !exists {
		h.clients[client.UserID] = make(map[string]*Client)
	}

	h.clients[client.UserID][client.DeviceID] = client

	h.updateStats(func(s *HubStats) {
		s.TotalConnections++
		s.ActiveConnections = h.countActiveConnections()
		s.LastActivity = time.Now()
	})

	if h.presence != nil {
		ctx := context.Background()
		h.presence.SetUserOnline(ctx, client.UserID, client.DeviceID)
	}

	log.Printf("Client registered: UserID=%s, DeviceID=%s", client.UserID, client.DeviceID)

	h.deliverPendingMessages(client)
}

func (h *Hub) unregisterClient(client *Client) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if devices, exists := h.clients[client.UserID]; exists {
		if _, exists := devices[client.DeviceID]; exists {
			delete(devices, client.DeviceID)
			client.Close()

			if len(devices) == 0 {
				delete(h.clients, client.UserID)
			}

			h.updateStats(func(s *HubStats) {
				s.ActiveConnections = h.countActiveConnections()
			})

			if h.presence != nil {
				ctx := context.Background()
				if len(devices) == 0 {
					h.presence.SetUserOffline(ctx, client.UserID)
				}
			}

			log.Printf("Client unregistered: UserID=%s, DeviceID=%s", client.UserID, client.DeviceID)
		}
	}
}

func (h *Hub) relayMessage(msg *RelayMessage) {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	if devices, exists := h.clients[msg.To]; exists {
		serverMsg := NewServerMessage(msg.Type, msg.From, msg.Payload)
		data, err := json.Marshal(serverMsg)
		if err != nil {
			log.Printf("Failed to marshal message: %v", err)
			return
		}

		delivered := false
		for deviceID, client := range devices {
			select {
			case client.send <- data:
				delivered = true
				log.Printf("Message relayed: From=%s To=%s Device=%s", msg.From, msg.To, deviceID)
			default:
				log.Printf("Client buffer full: UserID=%s DeviceID=%s", msg.To, deviceID)
			}
		}

		if delivered {
			h.updateStats(func(s *HubStats) {
				s.MessagesRelayed++
				s.LastActivity = time.Now()
			})
		}
	} else {
		if msg.Type == MessageTypeText && h.presence != nil {
			ctx := context.Background()
			h.presence.StorePendingMessage(ctx, msg.To, msg)
		}
		log.Printf("User offline, message stored: To=%s", msg.To)
	}
}

func (h *Hub) deliverPendingMessages(client *Client) {
	if h.presence == nil {
		return
	}

	ctx := context.Background()
	messages := h.presence.GetPendingMessages(ctx, client.UserID)

	for _, msgData := range messages {
		var msg RelayMessage
		if err := json.Unmarshal([]byte(msgData), &msg); err != nil {
			continue
		}

		serverMsg := NewServerMessage(msg.Type, msg.From, msg.Payload)
		if data, err := json.Marshal(serverMsg); err == nil {
			select {
			case client.send <- data:
				log.Printf("Delivered pending message to %s", client.UserID)
			default:
			}
		}
	}

	h.presence.ClearPendingMessages(ctx, client.UserID)
}

func (h *Hub) cleanup() {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	now := time.Now()
	for userID, devices := range h.clients {
		for deviceID, client := range devices {
			if now.Sub(client.GetLastActive()) > 5*time.Minute {
				log.Printf("Removing inactive client: UserID=%s DeviceID=%s", userID, deviceID)
				delete(devices, deviceID)
				client.Close()
			}
		}
		if len(devices) == 0 {
			delete(h.clients, userID)
		}
	}
}

func (h *Hub) GetStats() HubStats {
	h.statsMu.RLock()
	defer h.statsMu.RUnlock()
	return *h.stats
}

func (h *Hub) GetUserClients(userID string) []*Client {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	var clients []*Client
	if devices, exists := h.clients[userID]; exists {
		for _, client := range devices {
			clients = append(clients, client)
		}
	}
	return clients
}

func (h *Hub) BroadcastToUser(userID string, message []byte) {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	if devices, exists := h.clients[userID]; exists {
		for _, client := range devices {
			select {
			case client.send <- message:
			default:
			}
		}
	}
}

func (h *Hub) countActiveConnections() int {
	count := 0
	for _, devices := range h.clients {
		count += len(devices)
	}
	return count
}

func (h *Hub) updateStats(fn func(*HubStats)) {
	h.statsMu.Lock()
	defer h.statsMu.Unlock()
	fn(h.stats)
}
