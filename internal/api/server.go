package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"go-trade/internal/model"

	"go.uber.org/zap"
)

// EngineReader provides read-only access to engine state.
type EngineReader interface {
	StatusJSON() ([]byte, error)
	PushCommand(cmd model.Command)
	GridStatesJSON() ([]byte, error)
}

// Server is the REST API + WebSocket server.
type Server struct {
	engine  EngineReader
	hub     *Hub
	logger  *zap.Logger
	mux     *http.ServeMux
	srv     *http.Server
	address string
}

// NewServer creates an API server.
func NewServer(address string, engine EngineReader, logger *zap.Logger) *Server {
	s := &Server{
		engine:  engine,
		hub:     NewHub(logger),
		logger:  logger,
		mux:     http.NewServeMux(),
		address: address,
	}
	s.registerRoutes()
	return s
}

// Hub returns the WebSocket hub for broadcasting.
func (s *Server) HubRef() *Hub {
	return s.hub
}

func (s *Server) registerRoutes() {
	s.mux.HandleFunc("/api/status", s.handleStatus)
	s.mux.HandleFunc("/api/positions", s.handlePositions)
	s.mux.HandleFunc("/api/accounts", s.handleAccounts)
	s.mux.HandleFunc("/api/grids", s.handleGrids)
	s.mux.HandleFunc("/api/command", s.handleCommand)
	s.mux.HandleFunc("/api/health", s.handleHealth)
	s.mux.HandleFunc("/ws", s.handleWebSocket)
}

// Run starts the HTTP server and the WebSocket hub.
func (s *Server) Run(ctx context.Context) error {
	go s.hub.Run(ctx)

	s.srv = &http.Server{
		Addr:    s.address,
		Handler: corsMiddleware(s.mux),
	}

	errCh := make(chan error, 1)
	go func() {
		s.logger.Info("api_server_started", zap.String("address", s.address))
		if err := s.srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	select {
	case <-ctx.Done():
		shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return s.srv.Shutdown(shutCtx)
	case err := <-errCh:
		return err
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, model.APIResponse{
		Data:      map[string]string{"status": "ok"},
		Timestamp: time.Now(),
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	data, err := s.engine.StatusJSON()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, model.APIResponse{
			Error:     err.Error(),
			Timestamp: time.Now(),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}

func (s *Server) handlePositions(w http.ResponseWriter, r *http.Request) {
	data, err := s.engine.StatusJSON()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, model.APIResponse{
			Error:     err.Error(),
			Timestamp: time.Now(),
		})
		return
	}
	// Extract positions from status
	var status map[string]json.RawMessage
	json.Unmarshal(data, &status)
	snapshot := status["snapshot"]
	var snap map[string]json.RawMessage
	json.Unmarshal(snapshot, &snap)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(snap["positions"])
}

func (s *Server) handleAccounts(w http.ResponseWriter, r *http.Request) {
	data, err := s.engine.StatusJSON()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, model.APIResponse{
			Error:     err.Error(),
			Timestamp: time.Now(),
		})
		return
	}
	var status map[string]json.RawMessage
	json.Unmarshal(data, &status)
	snapshot := status["snapshot"]
	var snap map[string]json.RawMessage
	json.Unmarshal(snapshot, &snap)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(snap["accounts"])
}

func (s *Server) handleGrids(w http.ResponseWriter, r *http.Request) {
	data, err := s.engine.GridStatesJSON()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, model.APIResponse{
			Error:     err.Error(),
			Timestamp: time.Now(),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}

func (s *Server) handleCommand(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, model.APIResponse{
			Error:     "POST required",
			Timestamp: time.Now(),
		})
		return
	}

	var cmd model.Command
	if err := json.NewDecoder(r.Body).Decode(&cmd); err != nil {
		writeJSON(w, http.StatusBadRequest, model.APIResponse{
			Error:     "invalid JSON: " + err.Error(),
			Timestamp: time.Now(),
		})
		return
	}

	cmd.Time = time.Now()
	s.engine.PushCommand(cmd)

	s.logger.Info("api_command",
		zap.String("type", string(cmd.Type)),
		zap.String("symbol", cmd.Symbol),
		zap.String("account", cmd.AccountID),
	)

	writeJSON(w, http.StatusOK, model.APIResponse{
		Data:      map[string]string{"status": "queued"},
		Timestamp: time.Now(),
	})
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	s.hub.HandleUpgrade(w, r)
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Hub manages WebSocket client connections and broadcasting.
type Hub struct {
	clients    map[*WSClient]bool
	broadcast  chan []byte
	register   chan *WSClient
	unregister chan *WSClient
	mu         sync.RWMutex
	logger     *zap.Logger
}

// NewHub creates a WebSocket hub.
func NewHub(logger *zap.Logger) *Hub {
	return &Hub{
		clients:    make(map[*WSClient]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *WSClient),
		unregister: make(chan *WSClient),
		logger:     logger,
	}
}

// Broadcast sends a message to all connected clients.
func (h *Hub) Broadcast(msgType string, data any) {
	msg := model.WSMessage{
		Type:      msgType,
		Data:      data,
		Timestamp: time.Now(),
	}
	buf, err := json.Marshal(msg)
	if err != nil {
		return
	}
	select {
	case h.broadcast <- buf:
	default:
		// Drop if channel full
	}
}

// ClientCount returns the number of connected clients.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Run processes hub events.
func (h *Hub) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			h.logger.Info("ws_client_connected", zap.Int("total", len(h.clients)))
		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
			}
			h.mu.Unlock()
			h.logger.Info("ws_client_disconnected", zap.Int("total", len(h.clients)))
		case msg := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- msg:
				default:
					go func(c *WSClient) {
						h.unregister <- c
					}(client)
				}
			}
			h.mu.RUnlock()
		}
	}
}

// HandleUpgrade upgrades an HTTP connection to a WebSocket connection.
// Uses a simple frame-based WebSocket implementation.
func (h *Hub) HandleUpgrade(w http.ResponseWriter, r *http.Request) {
	// Use hijacker for raw WebSocket
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "websocket not supported", http.StatusInternalServerError)
		return
	}

	conn, bufrw, err := hj.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Perform WebSocket handshake
	if err := wsHandshake(r, bufrw); err != nil {
		conn.Close()
		return
	}

	client := &WSClient{
		hub:  h,
		conn: conn,
		send: make(chan []byte, 256),
	}
	h.register <- client

	go client.writePump()
	go client.readPump()
}
