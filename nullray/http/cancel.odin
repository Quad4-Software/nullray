// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Owner-keyed HTTP cancel. Worker threads bind an owner (the Session pointer);
cancel_request(owner) aborts only that owner's sockets and flag, so cancelling
one tab leaves background tabs streaming. Threads with no bound owner are
never cancel targets.
*/

package http

import "base:runtime"
import "core:net"
import "core:sync"

g_cancel_mu: sync.Mutex
g_cancelled: map[rawptr]bool

g_active_mu: sync.Mutex
// Conn -> owner, so one owner can hold several conns (sequentially).
g_active_conn: map[^Conn]rawptr

g_owner_mu: sync.Mutex
// OS thread id -> cancel owner.
g_owners: map[int]rawptr

// Bind this thread to a cancel owner and return the previous binding so the
// caller can restore it. Synchronous child work (in-thread subagents) would
// otherwise erase the parent worker's binding.
bind_owner :: proc(owner: rawptr) -> rawptr {
	sync.mutex_lock(&g_owner_mu)
	defer sync.mutex_unlock(&g_owner_mu)
	tid := sync.current_thread_id()
	prev: rawptr
	if g_owners != nil {
		if v, found := g_owners[tid]; found {
			prev = v
		}
	}
	if owner == nil {
		if g_owners != nil {
			delete_key(&g_owners, tid)
		}
		return prev
	}
	if g_owners == nil {
		g_owners = make(map[int]rawptr, 0, runtime.heap_allocator())
	}
	g_owners[tid] = owner
	return prev
}

unbind_owner :: proc(prev: rawptr = nil) {
	sync.mutex_lock(&g_owner_mu)
	defer sync.mutex_unlock(&g_owner_mu)
	if g_owners == nil {
		return
	}
	tid := sync.current_thread_id()
	if prev == nil {
		delete_key(&g_owners, tid)
	} else {
		g_owners[tid] = prev
	}
}

owner_for_thread :: proc() -> rawptr {
	sync.mutex_lock(&g_owner_mu)
	defer sync.mutex_unlock(&g_owner_mu)
	if g_owners == nil {
		return nil
	}
	v, found := g_owners[sync.current_thread_id()]
	if !found {
		return nil
	}
	return v
}

// Explicit owner wins. Otherwise the calling thread's bound owner applies.
resolve_owner :: proc(owner: rawptr) -> rawptr {
	if owner != nil {
		return owner
	}
	return owner_for_thread()
}

cancel_request :: proc(owner: rawptr) {
	if owner == nil {
		return
	}
	sync.mutex_lock(&g_cancel_mu)
	if g_cancelled == nil {
		g_cancelled = make(map[rawptr]bool, 0, runtime.heap_allocator())
	}
	g_cancelled[owner] = true
	sync.mutex_unlock(&g_cancel_mu)
	// Drop the live socket so blocked TLS/HTTP reads wake up. Shutdown only,
	// the owning thread still owns Conn teardown.
	sync.mutex_lock(&g_active_mu)
	for c, o in g_active_conn {
		if o == owner {
			conn_abort_locked(c)
		}
	}
	sync.mutex_unlock(&g_active_mu)
}

cancel_clear :: proc(owner: rawptr) {
	if owner == nil {
		return
	}
	sync.mutex_lock(&g_cancel_mu)
	if g_cancelled != nil {
		delete_key(&g_cancelled, owner)
	}
	sync.mutex_unlock(&g_cancel_mu)
}

cancel_requested :: proc(owner: rawptr = nil) -> bool {
	owner := resolve_owner(owner)
	if owner == nil {
		return false
	}
	sync.mutex_lock(&g_cancel_mu)
	defer sync.mutex_unlock(&g_cancel_mu)
	if g_cancelled == nil {
		return false
	}
	// Two-value form: map indexing inserts a zero entry on miss in Odin,
	// which would grow the set on every uncancelled lookup.
	v, found := g_cancelled[owner]
	return found && v
}

conn_register_active :: proc(conn: ^Conn, owner: rawptr) {
	if conn == nil {
		return
	}
	// Resolve the bound thread owner here so request paths that pass nil
	// still register under the calling worker's session.
	owner := resolve_owner(owner)
	if owner == nil {
		return
	}
	conn.owner = owner
	sync.mutex_lock(&g_active_mu)
	if g_active_conn == nil {
		g_active_conn = make(map[^Conn]rawptr, 0, runtime.heap_allocator())
	}
	g_active_conn[conn] = owner
	sync.mutex_unlock(&g_active_mu)
}

conn_clear_active :: proc(conn: ^Conn) {
	if conn == nil {
		return
	}
	sync.mutex_lock(&g_active_mu)
	if g_active_conn != nil {
		delete_key(&g_active_conn, conn)
	}
	sync.mutex_unlock(&g_active_mu)
}

// Wake a blocked read without freeing TLS state. The owning thread still runs
// conn_close and releases the socket and TLS context itself.
@(private)
conn_abort_locked :: proc(conn: ^Conn) {
	if conn == nil || conn.sock == 0 {
		return
	}
	_ = net.shutdown(conn.sock, .Both)
}
