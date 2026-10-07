// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Client connections. --acp uses one stdio conn (fd < 0 writes to stdout),
nullray serve registers one conn per accepted unix socket. Writes are
serialized per conn. Notifications for a session go to the owning conn
(the one that ran session/new) plus every conn that sent
session/subscribe for it.
*/

package acp

import "core:os"
import "core:strings"
import "core:sync"
import "nullray:mcp"

conn_new :: proc(srv: ^Server, fd: int) -> ^Conn {
	c := new(Conn)
	c.srv = srv
	c.fd = fd
	c.subs = make(map[string]bool)
	sync.mutex_lock(&srv.conns_mu)
	c.id = srv.next_conn
	srv.next_conn += 1
	srv.conns[c.id] = c
	sync.mutex_unlock(&srv.conns_mu)
	return c
}

// Mark the conn closed and drop it from the table. The struct stays
// allocated until server shutdown because sessions may still point at it
// through owner. The caller owns closing the fd.
conn_close :: proc(srv: ^Server, conn: ^Conn) {
	if conn == nil {
		return
	}
	sync.mutex_lock(&conn.mu)
	conn.closed = true
	sync.mutex_unlock(&conn.mu)
	sync.mutex_lock(&srv.conns_mu)
	delete_key(&srv.conns, conn.id)
	sync.mutex_unlock(&srv.conns_mu)
}

// Record a session subscription. notify_targets iterates subs under
// conns_mu, so writes take the same lock, a repeat subscribe does not
// leak a duplicate cloned key.
conn_subscribe :: proc(srv: ^Server, conn: ^Conn, session_id: string) {
	if conn == nil || len(session_id) == 0 {
		return
	}
	sync.mutex_lock(&srv.conns_mu)
	defer sync.mutex_unlock(&srv.conns_mu)
	if _, ok := conn.subs[session_id]; ok {
		return
	}
	conn.subs[strings.clone(session_id)] = true
}

conn_destroy :: proc(conn: ^Conn) {
	if conn == nil {
		return
	}
	delete(conn.subs)
	free(conn)
}

conns_destroy :: proc(srv: ^Server) {
	sync.mutex_lock(&srv.conns_mu)
	for _, c in srv.conns {
		conn_destroy(c)
	}
	clear(&srv.conns)
	// Owner pointers on live sessions dangle past this point, the server
	// teardown destroys sessions before conns, so this runs last.
	srv.stdin_conn = nil
	sync.mutex_unlock(&srv.conns_mu)
}

// All protocol writes for one conn go through here so notifications from
// worker threads never interleave with responses from the dispatch
// thread. A closed conn drops writes.
conn_write :: proc(conn: ^Conn, payload: string) {
	if conn == nil {
		return
	}
	sync.mutex_lock(&conn.mu)
	defer sync.mutex_unlock(&conn.mu)
	if conn.closed {
		return
	}
	if conn.fd < 0 {
		write_all_os(os.stdout, transmute([]u8)payload)
		write_all_os(os.stdout, transmute([]u8)string("\n"))
		return
	}
	conn_fd_write(conn.fd, transmute([]u8)payload)
	conn_fd_write(conn.fd, transmute([]u8)string("\n"))
}

@(private)
write_all_os :: proc(f: ^os.File, data: []u8) {
	total := 0
	for total < len(data) {
		n, err := os.write(f, data[total:])
		if n <= 0 || err != nil {
			return
		}
		total += n
	}
}

// Conns that receive notifications for session_id: the owning conn plus
// any conn that subscribed. Result is allocated with the given allocator.
notify_targets :: proc(srv: ^Server, session_id: string, allocator := context.temp_allocator) -> []^Conn {
	out := make([dynamic]^Conn, 0, 2, allocator)
	sync.mutex_lock(&srv.sessions_mu)
	owner: ^Conn
	if s, ok := srv.sessions[session_id]; ok {
		owner = s.owner
	}
	sync.mutex_unlock(&srv.sessions_mu)
	if owner != nil {
		append(&out, owner)
	}
	sync.mutex_lock(&srv.conns_mu)
	for _, c in srv.conns {
		if c == owner {
			continue
		}
		if c.subs[session_id] {
			append(&out, c)
		}
	}
	sync.mutex_unlock(&srv.conns_mu)
	return out[:]
}

notify_session :: proc(srv: ^Server, session_id: string, method: string, params_json: string) {
	payload := mcp.build_notification(method, params_json, context.temp_allocator)
	targets := notify_targets(srv, session_id, context.temp_allocator)
	for c in targets {
		conn_write(c, payload)
	}
}

// Wake the dispatch loop so it exits after the inbox drains. Used by the
// serve daemon on SIGTERM/SIGINT.
server_request_stop :: proc(srv: ^Server) {
	sync.mutex_lock(&srv.in_mu)
	srv.stop = true
	sync.cond_broadcast(&srv.in_cond)
	sync.mutex_unlock(&srv.in_mu)
}
