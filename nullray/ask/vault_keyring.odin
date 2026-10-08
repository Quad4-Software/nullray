// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Optional FreeDesktop Secret Service backend (secret-tool).

When NULLRAY_VAULT_BACKEND is keyring|secret|auto (default auto), and
secret-tool is available, vault puts also write to the user keyring and
gets fall back to lookup. Works with gnome-keyring, KWallet (compat),
KeePassXC Secret Service plugin, and anything else exposing
org.freedesktop.secrets.
*/

package ask

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:elevate"

KEYRING_ATTR_SERVICE_DEFAULT :: "nullray"
KEYRING_TOOL :: "secret-tool"
KEYRING_TIMEOUT_MS :: 8_000

Vault_Backend :: enum {
	Memory,  // in-process only
	Keyring, // FreeDesktop secrets via secret-tool
	Auto,    // keyring when tool exists, else memory
}

g_backend_once: sync.Once
g_backend: Vault_Backend
g_keyring_ok: bool
g_keyring_tool: string // absolute path or empty

vault_backend_from_env :: proc() -> Vault_Backend {
	if v, ok := os.lookup_env(constants.ENV_VAULT_BACKEND, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "memory", "mem", "ram", "off", "0", "none":
			return .Memory
		case "keyring", "secret", "secrets", "secret-service", "libsecret", "1", "on":
			return .Keyring
		case "auto", "":
			return .Auto
		}
	}
	return .Auto
}

keyring_service_name :: proc() -> string {
	if v, ok := os.lookup_env(constants.ENV_KEYRING_SERVICE, context.temp_allocator); ok {
		s := strings.trim_space(v)
		if len(s) > 0 {
			return s
		}
	}
	return KEYRING_ATTR_SERVICE_DEFAULT
}

vault_backend_ensure :: proc() {
	sync.once_do(&g_backend_once, proc() {
		g_backend = vault_backend_from_env()
		g_keyring_tool = keyring_find_tool()
		g_keyring_ok = len(g_keyring_tool) > 0
		if g_backend == .Auto {
			if g_keyring_ok {
				g_backend = .Keyring
			} else {
				g_backend = .Memory
			}
		} else if g_backend == .Keyring && !g_keyring_ok {
			// Requested keyring but tool missing: stay keyring-flagged but ops no-op to disk.
			g_keyring_ok = false
		}
	})
}

vault_backend_active :: proc() -> Vault_Backend {
	vault_backend_ensure()
	return g_backend
}

vault_keyring_available :: proc() -> bool {
	vault_backend_ensure()
	return g_keyring_ok
}

vault_backend_status_line :: proc(allocator := context.allocator) -> string {
	vault_backend_ensure()
	svc := keyring_service_name()
	switch g_backend {
	case .Memory:
		return strings.clone("vault backend=memory", allocator)
	case .Keyring:
		if g_keyring_ok {
			return fmt.aprintf("vault backend=keyring tool=%s service=%s", g_keyring_tool, svc, allocator = allocator)
		}
		return strings.clone("vault backend=keyring (secret-tool missing)", allocator)
	case .Auto:
		return strings.clone("vault backend=auto", allocator)
	}
	return strings.clone("vault backend=?", allocator)
}

@(private)
keyring_find_tool :: proc() -> string {
	// Prefer explicit path, then PATH, then common locations.
	if v, ok := os.lookup_env(constants.ENV_SECRET_TOOL, context.temp_allocator); ok {
		p := strings.trim_space(v)
		if len(p) > 0 && os.is_file(p) {
			return strings.clone(p)
		}
	}
	if p := keyring_lookup_path(KEYRING_TOOL); len(p) > 0 {
		return p
	}
	cands := []string{"/usr/bin/secret-tool", "/usr/local/bin/secret-tool", "/bin/secret-tool"}
	for c in cands {
		if os.is_file(c) {
			return strings.clone(c)
		}
	}
	return ""
}

@(private)
keyring_lookup_path :: proc(name: string) -> string {
	path, ok := os.lookup_env("PATH", context.temp_allocator)
	if !ok {
		return ""
	}
	for dir in strings.split(path, ":", context.temp_allocator) {
		d := strings.trim_space(dir)
		if len(d) == 0 {
			continue
		}
		cand, jerr := filepath.join({d, name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if os.is_file(cand) {
			return strings.clone(cand)
		}
	}
	return ""
}

// Store under service=nullray name=<name>. Returns false if keyring unused/failed.
keyring_store :: proc(name, value: string) -> bool {
	vault_backend_ensure()
	if g_backend != .Keyring || !g_keyring_ok || len(name) == 0 {
		return false
	}
	svc := keyring_service_name()
	label := fmt.tprintf("nullray:%s", name)
	// secret-tool requires --label=VALUE (equals form).
	label_flag := fmt.tprintf("--label=%s", label)
	argv := []string{
		g_keyring_tool, "store",
		label_flag,
		"service", svc,
		"name", name,
	}
	code, out, err := keyring_run(argv, value)
	_ = out
	_ = err
	return code == 0
}

keyring_lookup :: proc(name: string, allocator := context.allocator) -> (value: string, ok: bool) {
	vault_backend_ensure()
	if g_backend != .Keyring || !g_keyring_ok || len(name) == 0 {
		return "", false
	}
	svc := keyring_service_name()
	argv := []string{
		g_keyring_tool, "lookup",
		"service", svc,
		"name", name,
	}
	code, out, _ := keyring_run(argv, "")
	if code != 0 {
		return "", false
	}
	val := strings.trim_right_space(out)
	if len(val) == 0 {
		return "", false
	}
	return strings.clone(val, allocator), true
}

keyring_clear :: proc(name: string) -> bool {
	vault_backend_ensure()
	if g_backend != .Keyring || !g_keyring_ok || len(name) == 0 {
		return false
	}
	svc := keyring_service_name()
	argv := []string{
		g_keyring_tool, "clear",
		"service", svc,
		"name", name,
	}
	code, _, _ := keyring_run(argv, "")
	return code == 0
}

// List attribute.name values for service=nullray from secret-tool search --all.
keyring_list_names :: proc(allocator := context.allocator) -> []string {
	vault_backend_ensure()
	if g_backend != .Keyring || !g_keyring_ok {
		return nil
	}
	svc := keyring_service_name()
	argv := []string{
		g_keyring_tool, "search", "--all",
		"service", svc,
	}
	code, out, _ := keyring_run(argv, "")
	if code != 0 || len(out) == 0 {
		return nil
	}
	seen: map[string]bool
	seen = make(map[string]bool, context.temp_allocator)
	out_names := make([dynamic]string, allocator)
	for line in strings.split_lines(out, context.temp_allocator) {
		l := strings.trim_space(line)
		// attribute.name = FOO
		if strings.has_prefix(l, "attribute.name") {
			if eq := strings.index_byte(l, '='); eq >= 0 {
				n := strings.trim_space(l[eq + 1:])
				if len(n) > 0 && !seen[n] {
					seen[n] = true
					append(&out_names, strings.clone(n, allocator))
				}
			}
		}
	}
	return out_names[:]
}

/*
Run secret-tool. stdin_text is written to stdin when non-empty (store).
Returns exit code, stdout (caller owns), stderr (caller owns; may be empty).
*/
@(private)
keyring_run :: proc(argv: []string, stdin_text: string, allocator := context.allocator) -> (code: int, stdout, stderr: string) {
	if len(argv) == 0 {
		return 127, "", strings.clone("no argv", allocator)
	}
	stdout_r, stdout_w, perr := os.pipe()
	if perr != nil {
		return 127, "", fmt.aprintf("pipe: %v", perr, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, perr2 := os.pipe()
	if perr2 != nil {
		os.close(stdout_w)
		return 127, "", fmt.aprintf("pipe: %v", perr2, allocator = allocator)
	}
	defer os.close(stderr_r)

	has_stdin := len(stdin_text) > 0
	stdin_r, stdin_w: ^os.File
	if has_stdin {
		sr, sw, perr3 := os.pipe()
		if perr3 != nil {
			os.close(stdout_w)
			os.close(stderr_w)
			return 127, "", fmt.aprintf("pipe: %v", perr3, allocator = allocator)
		}
		stdin_r, stdin_w = sr, sw
	}

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			command = argv,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		if has_stdin {
			desc.stdin = stdin_r
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if has_stdin {
			os.close(stdin_r)
		}
		if start_err != nil {
			if has_stdin {
				os.close(stdin_w)
			}
			return 127, "", fmt.aprintf("exec: %v", start_err, allocator = allocator)
		}
	}
	if has_stdin {
		_, _ = os.write(stdin_w, transmute([]u8)stdin_text)
		os.close(stdin_w)
	}

	out_b: strings.Builder
	err_b: strings.Builder
	strings.builder_init(&out_b, allocator)
	strings.builder_init(&err_b, allocator)
	buf: [1024]u8
	timeout := time.Millisecond * time.Duration(KEYRING_TIMEOUT_MS)
	start := time.now()
	stdout_done := false
	stderr_done := false
	state: os.Process_State
	timed_out := false

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			timed_out = true
			_ = os.process_kill(process)
			break
		}
		got := false
		if !stdout_done {
			has, _ := os.pipe_has_data(stdout_r)
			if has {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					got = true
					strings.write_bytes(&out_b, buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
		}
		if !stderr_done {
			has, _ := os.pipe_has_data(stderr_r)
			if has {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					got = true
					strings.write_bytes(&err_b, buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
		}
		wait_state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && wait_state.exited {
			state = wait_state
			// Drain remaining ready bytes without blocking forever.
			for {
				has, _ := os.pipe_has_data(stdout_r)
				if !has {
					break
				}
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					strings.write_bytes(&out_b, buf[:n])
				}
				if n <= 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					break
				}
			}
			for {
				has, _ := os.pipe_has_data(stderr_r)
				if !has {
					break
				}
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					strings.write_bytes(&err_b, buf[:n])
				}
				if n <= 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					break
				}
			}
			stdout_done = true
			stderr_done = true
			break
		}
		if !got {
			time.sleep(2 * time.Millisecond)
		}
	}
	if !state.exited {
		_ = os.process_kill(process)
		state, _ = os.process_wait(process)
	}
	if timed_out {
		delete(strings.to_string(out_b))
		delete(strings.to_string(err_b))
		return 124, "", strings.clone("secret-tool timeout", allocator)
	}
	code = state.exit_code
	if !state.exited {
		code = 1
	}
	stdout = strings.to_string(out_b)
	stderr = strings.to_string(err_b)
	return code, stdout, stderr
}
