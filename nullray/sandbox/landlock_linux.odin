#+build linux

/*
Landlock syscall wrappers and ABI-aware ruleset building.
See https://docs.kernel.org/userspace-api/landlock.html
*/

package sandbox

import "core:fmt"
import "core:strings"
import linux "core:sys/linux"

LANDLOCK_CREATE_RULESET_VERSION :: u32(1 << 0)

LANDLOCK_RULE_PATH_BENEATH :: u32(1)
LANDLOCK_RULE_NET_PORT :: u32(2)

LANDLOCK_ACCESS_FS_EXECUTE :: u64(1 << 0)
LANDLOCK_ACCESS_FS_WRITE_FILE :: u64(1 << 1)
LANDLOCK_ACCESS_FS_READ_FILE :: u64(1 << 2)
LANDLOCK_ACCESS_FS_READ_DIR :: u64(1 << 3)
LANDLOCK_ACCESS_FS_REMOVE_DIR :: u64(1 << 4)
LANDLOCK_ACCESS_FS_REMOVE_FILE :: u64(1 << 5)
LANDLOCK_ACCESS_FS_MAKE_CHAR :: u64(1 << 6)
LANDLOCK_ACCESS_FS_MAKE_DIR :: u64(1 << 7)
LANDLOCK_ACCESS_FS_MAKE_REG :: u64(1 << 8)
LANDLOCK_ACCESS_FS_MAKE_SOCK :: u64(1 << 9)
LANDLOCK_ACCESS_FS_MAKE_FIFO :: u64(1 << 10)
LANDLOCK_ACCESS_FS_MAKE_BLOCK :: u64(1 << 11)
LANDLOCK_ACCESS_FS_MAKE_SYM :: u64(1 << 12)
LANDLOCK_ACCESS_FS_REFER :: u64(1 << 13)
LANDLOCK_ACCESS_FS_TRUNCATE :: u64(1 << 14)
LANDLOCK_ACCESS_FS_IOCTL_DEV :: u64(1 << 15)
LANDLOCK_ACCESS_FS_RESOLVE_UNIX :: u64(1 << 16)

LANDLOCK_ACCESS_NET_BIND_TCP :: u64(1 << 0)
LANDLOCK_ACCESS_NET_CONNECT_TCP :: u64(1 << 1)

LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET :: u64(1 << 0)
LANDLOCK_SCOPE_SIGNAL :: u64(1 << 1)

LANDLOCK_RESTRICT_SELF_TSYNC :: u32(1 << 3)

PR_SET_NO_NEW_PRIVS :: i32(38)

Ruleset_Attr :: struct {
	handled_access_fs:  u64,
	handled_access_net: u64,
	scoped:             u64,
}

Path_Beneath_Attr :: struct #packed {
	allowed_access: u64,
	parent_fd:      i32,
}

Net_Port_Attr :: struct {
	allowed_access: u64,
	port:           u64,
}

FS_READ :: LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR | LANDLOCK_ACCESS_FS_EXECUTE
FS_RW :: FS_READ |
	LANDLOCK_ACCESS_FS_WRITE_FILE |
	LANDLOCK_ACCESS_FS_TRUNCATE |
	LANDLOCK_ACCESS_FS_REMOVE_FILE |
	LANDLOCK_ACCESS_FS_REMOVE_DIR |
	LANDLOCK_ACCESS_FS_MAKE_REG |
	LANDLOCK_ACCESS_FS_MAKE_DIR |
	LANDLOCK_ACCESS_FS_MAKE_SYM

landlock_abi_version :: proc() -> (abi: int, ok: bool) {
	ret := linux.syscall(
		linux.SYS_landlock_create_ruleset,
		uintptr(0),
		uintptr(0),
		uintptr(LANDLOCK_CREATE_RULESET_VERSION),
	)
	if ret < 0 {
		return 0, false
	}
	return int(ret), true
}

landlock_create_ruleset :: proc(attr: ^Ruleset_Attr) -> (fd: linux.Fd, err: linux.Errno) {
	ret := linux.syscall(
		linux.SYS_landlock_create_ruleset,
		uintptr(rawptr(attr)),
		uintptr(size_of(Ruleset_Attr)),
		uintptr(0),
	)
	if ret < 0 {
		return -1, linux.Errno(-ret)
	}
	return linux.Fd(ret), .NONE
}

landlock_add_path :: proc(ruleset: linux.Fd, path: string, access: u64) -> linux.Errno {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	pfd, oerr := linux.open(cpath, {.PATH, .CLOEXEC})
	if oerr != .NONE {
		return oerr
	}
	defer linux.close(pfd)
	attr := Path_Beneath_Attr{
		allowed_access = access,
		parent_fd = i32(pfd),
	}
	ret := linux.syscall(
		linux.SYS_landlock_add_rule,
		uintptr(ruleset),
		uintptr(LANDLOCK_RULE_PATH_BENEATH),
		uintptr(rawptr(&attr)),
		uintptr(0),
	)
	if ret < 0 {
		return linux.Errno(-ret)
	}
	return .NONE
}

landlock_add_net_port :: proc(ruleset: linux.Fd, port: u64, access: u64) -> linux.Errno {
	attr := Net_Port_Attr{
		allowed_access = access,
		port = port,
	}
	ret := linux.syscall(
		linux.SYS_landlock_add_rule,
		uintptr(ruleset),
		uintptr(LANDLOCK_RULE_NET_PORT),
		uintptr(rawptr(&attr)),
		uintptr(0),
	)
	if ret < 0 {
		return linux.Errno(-ret)
	}
	return .NONE
}

landlock_restrict_self :: proc(ruleset: linux.Fd, flags: u32) -> linux.Errno {
	ret := linux.syscall(
		linux.SYS_landlock_restrict_self,
		uintptr(ruleset),
		uintptr(flags),
	)
	if ret < 0 {
		return linux.Errno(-ret)
	}
	return .NONE
}

mask_handled_for_abi :: proc(attr: ^Ruleset_Attr, abi: int) {
	if abi < 2 {
		attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_REFER
	}
	if abi < 3 {
		attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_TRUNCATE
	}
	if abi < 4 {
		attr.handled_access_net = 0
	}
	if abi < 5 {
		attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_IOCTL_DEV
	}
	if abi < 6 {
		attr.scoped = 0
	}
	if abi < 9 {
		attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_RESOLVE_UNIX
	}
}

set_no_new_privs :: proc() -> bool {
	err := linux.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)
	return err == .NONE
}

landlock_apply :: proc(cfg: Config, state: ^State) -> (ok: bool, msg: string) {
	abi, abi_ok := landlock_abi_version()
	if !abi_ok {
		return false, "landlock unavailable"
	}
	state.abi = abi

	attr := Ruleset_Attr{
		handled_access_fs =
			LANDLOCK_ACCESS_FS_EXECUTE |
			LANDLOCK_ACCESS_FS_WRITE_FILE |
			LANDLOCK_ACCESS_FS_READ_FILE |
			LANDLOCK_ACCESS_FS_READ_DIR |
			LANDLOCK_ACCESS_FS_REMOVE_DIR |
			LANDLOCK_ACCESS_FS_REMOVE_FILE |
			LANDLOCK_ACCESS_FS_MAKE_CHAR |
			LANDLOCK_ACCESS_FS_MAKE_DIR |
			LANDLOCK_ACCESS_FS_MAKE_REG |
			LANDLOCK_ACCESS_FS_MAKE_SOCK |
			LANDLOCK_ACCESS_FS_MAKE_FIFO |
			LANDLOCK_ACCESS_FS_MAKE_BLOCK |
			LANDLOCK_ACCESS_FS_MAKE_SYM |
			LANDLOCK_ACCESS_FS_REFER |
			LANDLOCK_ACCESS_FS_TRUNCATE |
			LANDLOCK_ACCESS_FS_IOCTL_DEV |
			LANDLOCK_ACCESS_FS_RESOLVE_UNIX,
		handled_access_net = 0,
		scoped = LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET | LANDLOCK_SCOPE_SIGNAL,
	}

	// Port filtering without UDP (ABI 10) breaks DNS for remote HTTPS.
	// Local mode only restricts TCP ports. Full mode leaves net unrestricted here.
	if cfg.net == .Local && abi >= 4 {
		attr.handled_access_net = LANDLOCK_ACCESS_NET_BIND_TCP | LANDLOCK_ACCESS_NET_CONNECT_TCP
	}

	mask_handled_for_abi(&attr, abi)

	ruleset, cerr := landlock_create_ruleset(&attr)
	if cerr != .NONE {
		return false, fmt.tprintf("landlock_create_ruleset: %v", cerr)
	}
	defer linux.close(ruleset)

	ro_access := FS_READ
	if abi >= 3 {
		ro_access |= LANDLOCK_ACCESS_FS_TRUNCATE
	}
	rw_access := FS_RW
	if abi < 3 {
		rw_access &= ~LANDLOCK_ACCESS_FS_TRUNCATE
	}

	ws_access := rw_access
	if cfg.fs == .RO {
		ws_access = ro_access
	}

	add_path :: proc(ruleset: linux.Fd, path: string, access: u64) -> bool {
		if len(path) == 0 {
			return true
		}
		err := landlock_add_path(ruleset, path, access)
		return err == .NONE
	}

	if !add_path(ruleset, cfg.workspace, ws_access) {
		return false, fmt.tprintf("landlock path failed: %s", cfg.workspace)
	}
	if !add_path(ruleset, cfg.config_dir, rw_access) {
		return false, fmt.tprintf("landlock path failed: %s", cfg.config_dir)
	}
	if !add_path(ruleset, cfg.tmp_dir, rw_access) {
		return false, fmt.tprintf("landlock path failed: %s", cfg.tmp_dir)
	}

	ro_roots := []string{"/usr", "/lib", "/lib64", "/etc/ssl", "/etc/ssl/certs", "/etc"}
	for root in ro_roots {
		_ = add_path(ruleset, root, ro_access)
	}
	_ = add_path(ruleset, "/dev", LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_READ_DIR)

	for p in cfg.extra_ro {
		_ = add_path(ruleset, p, ro_access)
	}
	for p in cfg.extra_rw {
		_ = add_path(ruleset, p, rw_access)
	}

	if attr.handled_access_net != 0 {
		ports := []u64{11434, 1234, 443, 80}
		for port in ports {
			_ = landlock_add_net_port(ruleset, port, LANDLOCK_ACCESS_NET_CONNECT_TCP)
		}
	}

	if !set_no_new_privs() {
		return false, "PR_SET_NO_NEW_PRIVS failed"
	}

	flags: u32 = 0
	if abi >= 8 {
		flags |= LANDLOCK_RESTRICT_SELF_TSYNC
	}
	rerr := landlock_restrict_self(ruleset, flags)
	if rerr != .NONE {
		return false, fmt.tprintf("landlock_restrict_self: %v", rerr)
	}
	return true, fmt.tprintf("landlock abi=%d", abi)
}
