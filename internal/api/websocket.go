package api

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
)

const wsMagicGUID = "258EAFA5-E914-47DA-95CA-5AB5AA29BE65"

// WSClient represents a single WebSocket client connection.
type WSClient struct {
	hub  *Hub
	conn net.Conn
	send chan []byte
}

// writePump sends messages from the hub to the WebSocket client.
func (c *WSClient) writePump() {
	defer func() {
		c.conn.Close()
	}()

	for msg := range c.send {
		if err := wsWriteFrame(c.conn, 1, msg); err != nil {
			return
		}
	}
}

// readPump reads messages from the WebSocket client (mainly for close/ping).
func (c *WSClient) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	for {
		_, _, err := wsReadFrame(c.conn)
		if err != nil {
			return
		}
	}
}

// wsHandshake performs the WebSocket upgrade handshake.
func wsHandshake(r *http.Request, bufrw *bufio.ReadWriter) error {
	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		return fmt.Errorf("missing Sec-WebSocket-Key")
	}

	h := sha1.New()
	h.Write([]byte(key + wsMagicGUID))
	accept := base64.StdEncoding.EncodeToString(h.Sum(nil))

	response := strings.Join([]string{
		"HTTP/1.1 101 Switching Protocols",
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Accept: " + accept,
		"", "",
	}, "\r\n")

	_, err := bufrw.WriteString(response)
	if err != nil {
		return err
	}
	return bufrw.Flush()
}

// wsWriteFrame writes a WebSocket frame (server → client, no masking).
func wsWriteFrame(w io.Writer, opcode byte, payload []byte) error {
	frame := make([]byte, 0, 10+len(payload))

	// First byte: FIN + opcode
	frame = append(frame, 0x80|opcode)

	// Payload length
	length := len(payload)
	switch {
	case length <= 125:
		frame = append(frame, byte(length))
	case length <= 65535:
		frame = append(frame, 126)
		buf := make([]byte, 2)
		binary.BigEndian.PutUint16(buf, uint16(length))
		frame = append(frame, buf...)
	default:
		frame = append(frame, 127)
		buf := make([]byte, 8)
		binary.BigEndian.PutUint64(buf, uint64(length))
		frame = append(frame, buf...)
	}

	frame = append(frame, payload...)
	_, err := w.Write(frame)
	return err
}

// wsReadFrame reads a WebSocket frame (client → server, with masking).
func wsReadFrame(r io.Reader) (opcode byte, payload []byte, err error) {
	header := make([]byte, 2)
	if _, err = io.ReadFull(r, header); err != nil {
		return
	}

	opcode = header[0] & 0x0F
	masked := header[1]&0x80 != 0
	length := uint64(header[1] & 0x7F)

	switch length {
	case 126:
		buf := make([]byte, 2)
		if _, err = io.ReadFull(r, buf); err != nil {
			return
		}
		length = uint64(binary.BigEndian.Uint16(buf))
	case 127:
		buf := make([]byte, 8)
		if _, err = io.ReadFull(r, buf); err != nil {
			return
		}
		length = binary.BigEndian.Uint64(buf)
	}

	var maskKey [4]byte
	if masked {
		if _, err = io.ReadFull(r, maskKey[:]); err != nil {
			return
		}
	}

	payload = make([]byte, length)
	if _, err = io.ReadFull(r, payload); err != nil {
		return
	}

	if masked {
		for i := range payload {
			payload[i] ^= maskKey[i%4]
		}
	}

	// Handle close frame
	if opcode == 8 {
		err = fmt.Errorf("close frame received")
	}

	return
}
