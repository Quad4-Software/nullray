// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
Unix socket listener for nullray serve. Path: NULLRAY_SERVE_SOCK, else
$XDG_RUNTIME_DIR/nullray/nullray.sock, else ~/.config/nullray/nullray.sock.
The parent dir is created 0700 and the socket node chmod 0600. On bind
failure the existing node is probed: a live daemon errors out, a stale
socket is unlinked and rebound.
*/

package serve

import c "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"
import "nullray:constants"
import "nullray:sandbox"

SUN_PATH_MAX :: 108 // posix.sockaddr_un.sun_path on Linux; BSD is 104.

// Directory the socket lives in. Used by cmd for sandbox grants.
sock_dir :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_SERVE_SOCK, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(filepath.dir(v), allocator)
	}
	if xdg, ok := os.lookup_env("XDG_RUNTIME_DIR", context.temp_allocator); ok && len(xdg) > 0 {
		joined, jerr := filepath.join({xdg, constants.CONFIG_DIR_NAME}, allocator)
		if jerr == nil {
			return joined
		}
	}
	return sandbox.resolve_config_dir(allocator)
}

sock_path :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_SERVE_SOCK, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	dir := sock_dir(context.temp_allocator)
	joined, err := filepath.join({dir, constants.SERVE_SOCK_NAME}, allocator)
	if err != nil {
		return ""
	}
	return joined
}

@(private)
make_sockaddr :: proc(path: string) -> (addr: posix.sockaddr_un, addr_len: posix.socklen_t, ok: bool) {
	if len(path) == 0 || len(path) >= SUN_PATH_MAX {
		return {}, 0, false
	}
	addr.sun_family = .UNIX
	path_off := int(offset_of(posix.sockaddr_un, sun_path))
	when ODIN_OS != .Linux {
		addr.sun_len = c.uchar(path_off + len(path) + 1)
	}
	for ch, i in path {
		addr.sun_path[i] = c.char(ch)
	}
	addr_len = posix.socklen_t(path_off + len(path) + 1)
	return addr, addr_len, true
}

// True when a peer accepts a connection on path (a live daemon).
sock_live :: proc(path: string) -> bool {
	fd := posix.socket(.UNIX, .STREAM)
	if fd < 0 {
		return false
	}
	defer posix.close(fd)
	addr, alen, ok := make_sockaddr(path)
	if !ok {
		return false
	}
	return posix.connect(fd, cast(^posix.sockaddr)&addr, alen) == .OK
}

// Connect to the daemon socket. err is "" on success.
sock_connect :: proc(path: string) -> (fd: posix.FD, err: string) {
	addr, alen, ok := make_sockaddr(path)
	if !ok {
		return -1, "socket path too long"
	}
	fd = posix.socket(.UNIX, .STREAM)
	if fd < 0 {
		return -1, fmt.tprintf("socket: %v", posix.errno())
	}
	if posix.connect(fd, cast(^posix.sockaddr)&addr, alen) != .OK {
		e := posix.errno()
		posix.close(fd)
		return -1, fmt.tprintf("connect %s: %v", path, e)
	}
	return fd, ""
}

unix_listen :: proc(path: string) -> (fd: posix.FD, err: string) {
	addr, alen, ok := make_sockaddr(path)
	if !ok {
		return -1, fmt.tprintf("socket path too long: %s", path)
	}
	fd = posix.socket(.UNIX, .STREAM)
	if fd < 0 {
		return -1, fmt.tprintf("socket: %v", posix.errno())
	}
	bound := false
	for attempt in 0 ..= 1 {
		if posix.bind(fd, cast(^posix.sockaddr)&addr, alen) == .OK {
			bound = true
			break
		}
		e := posix.errno()
		if e == .EADDRINUSE && attempt == 0 {
			if sock_live(path) {
				posix.close(fd)
				return -1, fmt.tprintf("another nullray serve is already running on %s", path)
			}
			// Stale socket node: no listener accepts, so reclaim it.
			_ = os.remove(path)
			continue
		}
		posix.close(fd)
		return -1, fmt.tprintf("bind %s: %v", path, e)
	}
	if !bound {
		posix.close(fd)
		return -1, fmt.tprintf("bind %s failed", path)
	}
	// fchmod rejects sockets on Linux; chmod the bound path instead.
	_ = posix.chmod(strings.clone_to_cstring(path, context.temp_allocator), posix.mode_t{.IRUSR, .IWUSR})
	if posix.listen(fd, 16) != .OK {
		e := posix.errno()
		posix.close(fd)
		return -1, fmt.tprintf("listen %s: %v", path, e)
	}
	return fd, ""
}

Prebind :: struct {
	fd:   int,    // <0 when failed (posix.FD)
	path: string, // owned
	err:  string, // owned; set when fd < 0
}

// Resolve the socket path, mkdir the parent 0700, and bind+listen. Runs
// before sandbox apply so Landlock MAKE_SOCK cannot block the bind.
prebind :: proc() -> Prebind {
	pb: Prebind
	pb.fd = -1
	pb.path = sock_path(context.allocator)
	if len(pb.path) == 0 {
		pb.err = strings.clone("could not resolve socket path")
		return pb
	}
	dir := filepath.dir(pb.path)
	// EEXIST is fine: the dir is allowed to already be there.
	_ = os.make_directory_all(dir, os.perm_number(0o700))
	if !os.exists(dir) {
		pb.err = fmt.aprintf("mkdir %s failed", dir)
		return pb
	}
	fd, err := unix_listen(pb.path)
	if len(err) > 0 {
		pb.err = strings.clone(err)
		return pb
	}
	pb.fd = int(fd)
	return pb
}

prebind_destroy :: proc(pb: ^Prebind) {
	if pb == nil {
		return
	}
	delete(pb.path)
	delete(pb.err)
	pb^ = {}
}
