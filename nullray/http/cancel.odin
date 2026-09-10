// SPDX-License-Identifier: 0BSD
/*
Global HTTP cancel flag so Esc/stop can abort in-flight requests.
*/

package http

import "core:sync"

g_cancel_mu: sync.Mutex
g_cancel: bool

g_active_mu: sync.Mutex
g_active_conn: ^Conn

cancel_request :: proc() {
	sync.mutex_lock(&g_cancel_mu)
	g_cancel = true
	sync.mutex_unlock(&g_cancel_mu)
	// Drop the live socket so blocked TLS/HTTP reads wake up.
	sync.mutex_lock(&g_active_mu)
	c := g_active_conn
	sync.mutex_unlock(&g_active_mu)
	if c != nil {
		conn_close(c)
	}
}

cancel_clear :: proc() {
	sync.mutex_lock(&g_cancel_mu)
	g_cancel = false
	sync.mutex_unlock(&g_cancel_mu)
}

cancel_requested :: proc() -> bool {
	sync.mutex_lock(&g_cancel_mu)
	defer sync.mutex_unlock(&g_cancel_mu)
	return g_cancel
}

conn_register_active :: proc(conn: ^Conn) {
	if conn == nil {
		return
	}
	sync.mutex_lock(&g_active_mu)
	g_active_conn = conn
	sync.mutex_unlock(&g_active_mu)
}

conn_clear_active :: proc(conn: ^Conn) {
	if conn == nil {
		return
	}
	sync.mutex_lock(&g_active_mu)
	if g_active_conn == conn {
		g_active_conn = nil
	}
	sync.mutex_unlock(&g_active_mu)
}
