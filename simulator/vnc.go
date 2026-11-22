package main

import (
	"log"
	"net"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

// vncProxy bridges the noVNC WebSocket to the Xvnc TCP port (what websockify does).
func vncProxy(addr string) http.HandlerFunc {
	up := websocket.Upgrader{
		Subprotocols:    []string{"binary"},
		ReadBufferSize:  64 << 10,
		WriteBufferSize: 64 << 10,
	}
	return func(w http.ResponseWriter, r *http.Request) {
		ws, err := up.Upgrade(w, r, nil)
		if err != nil {
			return // Upgrade already wrote the error
		}
		defer ws.Close()
		conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			log.Printf("vnc: %v", err)
			_ = ws.WriteControl(websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseTryAgainLater, "desktop not running"), time.Now().Add(time.Second))
			return
		}
		defer conn.Close()

		go func() { // VNC -> browser
			defer ws.Close()
			buf := make([]byte, 64<<10)
			for {
				n, err := conn.Read(buf)
				if n > 0 {
					if werr := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); werr != nil {
						return
					}
				}
				if err != nil {
					return
				}
			}
		}()
		for { // browser -> VNC
			_, data, err := ws.ReadMessage()
			if err != nil {
				return
			}
			if _, err := conn.Write(data); err != nil {
				return
			}
		}
	}
}
