// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
nullray serve: the ACP server over a unix socket so clients share one
warm daemon (providers, MCP, rate limits). Each accepted conn gets a
reader thread feeding the same acp dispatch machinery; notifications
reach the owning conn plus subscribers. SIGTERM/SIGINT stop the accept
loop, destroy sessions, and unlink the socket. A daemon crash drops
live sessions (same as opencode).
*/

package serve

import "core:fmt"
import "core:os"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"
import "nullray:acp"
import "nullray:schedule"

g_stop: b32

serve_on_signal :: proc "c" (sig: posix.Signal) {
	g_stop = true
}

Accept_Args :: struct {
	srv:       ^acp.Server,
	listen_fd: posix.FD,
	readers:   [dynamic]^thread.Thread,
	mu:        sync.Mutex,
}

accept_main :: proc(data: rawptr) {
	a := cast(^Accept_Args)data
	srv := a.srv
	for !g_stop {
		pfd := posix.pollfd{fd = a.listen_fd, events = {.IN}}
		n := posix.poll(&pfd, 1, 150)
		if n < 0 {
			if posix.errno() == .EINTR {
				continue
			}
			break
		}
		if n == 0 {
			continue
		}
		cfd := posix.accept(a.listen_fd, nil, nil)
		if cfd < 0 {
			if posix.errno() == .EINTR {
				continue
			}
			time.sleep(10 * time.Millisecond)
			continue
		}
		conn := acp.conn_new(srv, int(cfd))
		th := thread.create_and_start_with_data(conn, acp.conn_reader_main, nil, .Normal, false)
		if th == nil {
			acp.conn_close(srv, conn)
			_ = posix.close(cfd)
			continue
		}
		sync.mutex_lock(&a.mu)
		append(&a.readers, th)
		sync.mutex_unlock(&a.mu)
	}
	acp.server_request_stop(srv)
}

serve_ignore_signal :: proc "c" (sig: posix.Signal) {
}

install_serve_signals :: proc() {
	act: posix.sigaction_t
	act.sa_handler = serve_on_signal
	_ = posix.sigemptyset(&act.sa_mask)
	_ = posix.sigaction(.SIGTERM, &act, nil)
	_ = posix.sigaction(.SIGINT, &act, nil)
	ign: posix.sigaction_t
	ign.sa_handler = serve_ignore_signal
	_ = posix.sigemptyset(&ign.sa_mask)
	_ = posix.sigaction(.SIGPIPE, &ign, nil)
}

// listen_fd < 0 binds here; a prebound fd (from prebind, before the
// sandbox applied) is used as-is. Only a socket we bound ourselves is
// unlinked at shutdown: a caller-supplied listen_fd may name a file the
// caller owns (socket activation), so removing it would be wrong.
run_serve :: proc(listen_fd: int, path: string, bare: bool) -> int {
	fd := posix.FD(listen_fd)
	own_path := ""
	bound_here := false
	if fd < 0 {
		pb := prebind()
		if len(pb.err) > 0 {
			fmt.eprintln("nullray serve:", pb.err)
			prebind_destroy(&pb)
			return 1
		}
		fd = posix.FD(pb.fd)
		own_path = pb.path
		bound_here = true
	}
	sock_path := len(path) > 0 ? path : own_path
	install_serve_signals()

	srv := new(acp.Server)
	acp.server_runtime_init(srv, bare)
	defer acp.server_runtime_destroy(srv)

	// Durable jobs load at init; the watcher thread fires due work into
	// sessions via the scoped sink. NULLRAY_SCHEDULE=0 disables all of it.
	sched_on := false
	if schedule.schedule_enabled() {
		schedule.schedule_init()
		acp.schedule_bind(srv)
		schedule.schedule_start()
		sched_on = true
	}

	fmt.eprintf("nullray serve listening on %s\n", sock_path)

	a := new(Accept_Args)
	a.srv = srv
	a.listen_fd = fd
	a.readers = make([dynamic]^thread.Thread)
	accept_th := thread.create_and_start_with_data(a, accept_main, nil, .Normal, false)
	if accept_th == nil {
		fmt.eprintln("nullray serve: failed to start accept loop")
		if bound_here {
			_ = posix.close(fd)
			if len(own_path) > 0 {
				_ = os.remove(own_path)
			}
		}
		delete(a.readers)
		free(a)
		delete(own_path)
		return 1
	}

	acp.dispatch_loop(srv)

	thread.join(accept_th)
	thread.destroy(accept_th)
	// Shutdown live conn fds so reader threads hit EOF and close their
	// own fd (avoids a double close on fd reuse), then join them.
	sync.mutex_lock(&srv.conns_mu)
	for _, c in srv.conns {
		sync.mutex_lock(&c.mu)
		if !c.closed && c.fd >= 0 {
			_ = posix.shutdown(posix.FD(c.fd), .RDWR)
		}
		sync.mutex_unlock(&c.mu)
	}
	sync.mutex_unlock(&srv.conns_mu)
	sync.mutex_lock(&a.mu)
	for th in a.readers {
		thread.join(th)
		thread.destroy(th)
	}
	delete(a.readers)
	sync.mutex_unlock(&a.mu)
	free(a)

	// Stop the watcher before sessions are destroyed so a late emit
	// cannot race teardown.
	if sched_on {
		schedule.schedule_stop()
	}
	acp.server_teardown(srv)
	_ = posix.close(fd)
	if bound_here && len(own_path) > 0 {
		_ = os.remove(own_path)
	}
	delete(own_path)
	fmt.eprintln("nullray serve: stopped")
	return 0
}
