/*
Global HTTP cancel flag so Esc/stop can abort in-flight curl.
*/

package http

import "core:sync"

g_cancel_mu: sync.Mutex
g_cancel: bool

cancel_request :: proc() {
	sync.mutex_lock(&g_cancel_mu)
	g_cancel = true
	sync.mutex_unlock(&g_cancel_mu)
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
