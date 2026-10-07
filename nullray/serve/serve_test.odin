// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
Tests for the serve package: socket path resolution, ndjson framing on a
socketpair, stale socket detection, and session notify routing.
*/

package serve

import c "core:c"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "nullray:acp"
import "nullray:constants"

@(private)
with_env :: proc(key, value: string, body: proc(t: ^testing.T), t: ^testing.T) {
	prev, had := os.lookup_env(key, context.temp_allocator)
	prev_copy := strings.clone(prev)
	if len(value) > 0 {
		os.set_env(key, value)
	} else {
		os.unset_env(key)
	}
	defer {
		if had {
			os.set_env(key, prev_copy)
		} else {
			os.unset_env(key)
		}
		delete(prev_copy)
	}
	body(t)
}

@test
test_sock_path_env_override :: proc(t: ^testing.T) {
	with_env(constants.ENV_SERVE_SOCK, "/tmp/nullray-test-x.sock", proc(t: ^testing.T) {
		p := sock_path(context.temp_allocator)
		testing.expect(t, p == "/tmp/nullray-test-x.sock")
		d := sock_dir(context.temp_allocator)
		testing.expect(t, d == "/tmp")
	}, t)
}

@test
test_sock_path_default :: proc(t: ^testing.T) {
	with_env(constants.ENV_SERVE_SOCK, "", proc(t: ^testing.T) {
		p := sock_path(context.temp_allocator)
		testing.expect(t, len(p) > 0)
		testing.expect(t, strings.has_suffix(p, constants.SERVE_SOCK_NAME))
		testing.expect(t, strings.contains(p, "nullray"))
	}, t)
}

@test
test_framing_roundtrip_socketpair :: proc(t: ^testing.T) {
	fds: [2]posix.FD
	testing.expect(t, posix.socketpair(.UNIX, .STREAM, .IP, &fds) == .OK)
	defer posix.close(fds[0])
	defer posix.close(fds[1])

	cli: Client
	cli.fd = fds[0]
	cli.open = true
	defer delete(cli.carry)

	id := client_send(&cli, "initialize", `{"protocolVersion":1}`)
	testing.expect(t, id == 1)

	// Server side reads the framed request line.
	buf: [4096]u8
	n := posix.read(fds[1], raw_data(buf[:]), c.size_t(len(buf)))
	testing.expect(t, n > 0)
	got := string(buf[:n])
	testing.expect(t, strings.has_suffix(got, "\n"))
	testing.expect(t, strings.contains(got, `"method":"initialize"`))
	testing.expect(t, strings.contains(got, `"id":1`))

	// Server writes a response, client_read_line splits it back out.
	resp := `{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}` + "\n"
	w := posix.write(fds[1], raw_data(resp), c.size_t(len(resp)))
	testing.expect(t, w == c.ssize_t(len(resp)))
	line, ok := client_read_line(&cli, 1000)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(line, `"protocolVersion":1`))
	delete(line)
}

@test
test_stale_socket_detect :: proc(t: ^testing.T) {
	_ = os.make_directory_all("/tmp/nullray-serve-test")
	path := "/tmp/nullray-serve-test/stale.sock"
	defer os.remove(path)

	// Nothing bound: not live.
	testing.expect(t, !sock_live(path))

	// A real listener is live.
	fd, err := unix_listen(path)
	testing.expect(t, len(err) == 0, err)
	defer posix.close(fd)
	testing.expect(t, sock_live(path))

	// Rebind while live reports the running daemon.
	fd2, err2 := unix_listen(path)
	testing.expect(t, fd2 < 0)
	testing.expect(t, strings.contains(err2, "already running"))
}

@test
test_stale_socket_reclaim :: proc(t: ^testing.T) {
	path := "/tmp/nullray-serve-test/reclaim.sock"
	_ = os.make_directory_all("/tmp/nullray-serve-test")
	defer os.remove(path)

	// Dead node: a regular file where a socket used to be.
	f, ferr := os.open(path, os.O_CREATE | os.O_WRONLY)
	testing.expect(t, ferr == nil)
	os.close(f)
	testing.expect(t, !sock_live(path))

	// unix_listen sees EADDRINUSE, probes (not live), unlinks, rebinds.
	fd, err := unix_listen(path)
	testing.expect(t, len(err) == 0, err)
	defer posix.close(fd)
	testing.expect(t, sock_live(path))
}

@test
test_notify_targets_routing :: proc(t: ^testing.T) {
	srv: acp.Server
	srv.conns = make(map[int]^acp.Conn)
	defer delete(srv.conns)
	srv.sessions = make(map[string]^acp.Acp_Session)
	defer delete(srv.sessions)

	owner := acp.conn_new(&srv, -1)
	defer acp.conn_destroy(owner)
	watcher := acp.conn_new(&srv, -1)
	defer acp.conn_destroy(watcher)
	idle := acp.conn_new(&srv, -1)
	defer acp.conn_destroy(idle)

	s := new(acp.Acp_Session)
	s.id = strings.clone("acp-7")
	s.owner = owner
	srv.sessions[s.id] = s
	defer {
		delete(s.id)
		free(s)
	}

	// Only the owner gets updates.
	targets := acp.notify_targets(&srv, "acp-7")
	testing.expect(t, len(targets) == 1)
	testing.expect(t, targets[0] == owner)

	// A subscriber joins, the idle conn stays out.
	watcher.subs["acp-7"] = true
	targets = acp.notify_targets(&srv, "acp-7")
	testing.expect(t, len(targets) == 2)

	// Unknown session still reaches subscribers but no owner.
	other := acp.conn_new(&srv, -1)
	defer acp.conn_destroy(other)
	other.subs["acp-9"] = true
	targets = acp.notify_targets(&srv, "acp-9")
	testing.expect(t, len(targets) == 1)
	testing.expect(t, targets[0] == other)
}

@test
test_pick_session :: proc(t: ^testing.T) {
	raw := `{"jsonrpc":"2.0","id":2,"result":{"sessions":[{"sessionId":"acp-2","cwd":"/a"},{"sessionId":"acp-9","cwd":"/b"},{"sessionId":"acp-4","cwd":"/c"}]}}`
	best := attach_pick_session(raw)
	testing.expect(t, best == "acp-9")
}
