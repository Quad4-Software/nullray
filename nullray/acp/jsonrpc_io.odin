// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
ndjson framing for ACP. A shared line scanner feeds reader threads
(stdin for --acp, one per socket conn for serve), writers serialize per
conn under conn.mu. No Content-Length headers.
*/

package acp

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:mcp"

// Incremental newline splitter shared by the stdin reader and per-conn
// socket readers. Pushes an owned line copy per complete line.
Line_Scanner :: struct {
	carry: [dynamic]u8,
}

scan_feed :: proc(sc: ^Line_Scanner, srv: ^Server, conn: ^Conn, chunk: []u8) {
	append(&sc.carry, ..chunk)
	for {
		idx := -1
		for b, i in sc.carry {
			if b == '\n' {
				idx = i
				break
			}
		}
		if idx < 0 {
			break
		}
		line := strings.clone(string(sc.carry[:idx]))
		rest := len(sc.carry) - idx - 1
		copy(sc.carry[:rest], sc.carry[idx + 1:])
		resize(&sc.carry, rest)
		push_inbound(srv, Inbound{line = line, conn = conn})
	}
}

// Push a trailing partial line on EOF.
scan_flush :: proc(sc: ^Line_Scanner, srv: ^Server, conn: ^Conn) {
	if len(sc.carry) == 0 {
		return
	}
	line := strings.clone(string(sc.carry[:]))
	clear(&sc.carry)
	push_inbound(srv, Inbound{line = line, conn = conn})
}

reader_main :: proc(data: rawptr) {
	srv := cast(^Server)data
	sc: Line_Scanner
	defer delete(sc.carry)
	buf: [8192]u8
	for {
		n, _ := os.read(os.stdin, buf[:])
		if n > 0 {
			scan_feed(&sc, srv, srv.stdin_conn, buf[:n])
			continue
		}
		// n <= 0: EOF or read error. Flush a trailing partial line, then
		// wake the dispatcher so it can exit.
		scan_flush(&sc, srv, srv.stdin_conn)
		sync.mutex_lock(&srv.in_mu)
		srv.eof = true
		sync.cond_broadcast(&srv.in_cond)
		sync.mutex_unlock(&srv.in_mu)
		return
	}
}

// Socket conn reader (serve). On EOF the conn is marked closed and
// removed, the daemon stays up until srv.stop.
conn_reader_main :: proc(data: rawptr) {
	conn := cast(^Conn)data
	srv := conn.srv
	sc: Line_Scanner
	defer delete(sc.carry)
	buf: [8192]u8
	for {
		n := conn_fd_read(conn.fd, buf[:])
		if n > 0 {
			scan_feed(&sc, srv, conn, buf[:n])
			continue
		}
		scan_flush(&sc, srv, conn)
		conn_close(srv, conn)
		if conn.fd >= 0 {
			conn_fd_close(conn.fd)
		}
		return
	}
}

// --- outbound ----------------------------------------------------------

// Dispatch-thread writers target the conn currently being served.
// Worker threads must use the _conn variants with sess.owner.

send_result :: proc(srv: ^Server, id_json: string, result_json: string) {
	send_result_conn(srv.dispatch_conn, id_json, result_json)
}

send_result_conn :: proc(conn: ^Conn, id_json: string, result_json: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	strings.write_string(&b, len(id_json) > 0 ? id_json : "null")
	strings.write_string(&b, `,"result":`)
	strings.write_string(&b, len(result_json) > 0 ? result_json : "{}")
	strings.write_byte(&b, '}')
	conn_write(conn, strings.to_string(b))
}

send_error :: proc(srv: ^Server, id_json: string, code: int, message: string) {
	send_error_conn(srv.dispatch_conn, id_json, code, message)
}

send_error_conn :: proc(conn: ^Conn, id_json: string, code: int, message: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	strings.write_string(&b, len(id_json) > 0 ? id_json : "null")
	strings.write_string(&b, `,"error":{"code":`)
	fmt.sbprint(&b, code)
	strings.write_string(&b, `,"message":`)
	mcp.write_json_string(&b, message)
	strings.write_string(&b, `}}`)
	conn_write(conn, strings.to_string(b))
}

send_request_conn :: proc(conn: ^Conn, id: int, method: string, params_json: string) {
	payload := mcp.build_request(id, method, params_json, context.temp_allocator)
	conn_write(conn, payload)
}
