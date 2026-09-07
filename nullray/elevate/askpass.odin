// SPDX-License-Identifier: 0BSD
/*
One-shot askpass secret stash shared by UI and --askpass.
*/

package elevate

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:strings"
import "nullray:constants"

g_stash_mu: sync.Mutex
g_stash: string
g_helper_path: string
g_secret_path: string

ENV_ASKPASS_SECRET :: "NULLRAY_ASKPASS_SECRET"

askpass_secret_path :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(ENV_ASKPASS_SECRET, context.temp_allocator); ok {
		trimmed := strings.trim_space(v)
		if len(trimmed) > 0 {
			return strings.clone(trimmed, allocator)
		}
	}
	dir := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = os.get_env("TMPDIR", context.temp_allocator)
	}
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, jerr := filepath.join({dir, fmt.tprintf("nullray-askpass-secret-%d", os.get_pid())}, allocator)
	if jerr != nil {
		return strings.clone("/tmp/nullray-askpass-secret", allocator)
	}
	return path
}

stash_askpass_secret :: proc(password: string) {
	sync.mutex_lock(&g_stash_mu)
	defer sync.mutex_unlock(&g_stash_mu)
	zero_and_delete(g_stash)
	g_stash = strings.clone(password)
	if len(g_secret_path) > 0 {
		delete(g_secret_path)
	}
	g_secret_path = askpass_secret_path()
	_ = os.remove(g_secret_path)
	_ = os.write_entire_file(g_secret_path, transmute([]byte)password)
	when ODIN_OS != .Windows {
		_ = os.chmod(g_secret_path, os.perm(0o600))
	}
	os.set_env(ENV_ASKPASS_SECRET, g_secret_path)
}

clear_askpass_secret :: proc() {
	sync.mutex_lock(&g_stash_mu)
	defer sync.mutex_unlock(&g_stash_mu)
	zero_and_delete(g_stash)
	g_stash = {}
	if len(g_secret_path) > 0 {
		_ = os.remove(g_secret_path)
		delete(g_secret_path)
		g_secret_path = {}
	}
	if v, ok := os.lookup_env(ENV_ASKPASS_SECRET, context.temp_allocator); ok && len(v) > 0 {
		_ = os.remove(v)
	}
	os.unset_env(ENV_ASKPASS_SECRET)
}

take_askpass_secret :: proc(allocator := context.allocator) -> string {
	sync.mutex_lock(&g_stash_mu)
	if len(g_stash) > 0 {
		out := strings.clone(g_stash, allocator)
		zero_and_delete(g_stash)
		g_stash = {}
		sync.mutex_unlock(&g_stash_mu)
		return out
	}
	sync.mutex_unlock(&g_stash_mu)

	path := askpass_secret_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return ""
	}
	_ = os.remove(path)
	os.unset_env(ENV_ASKPASS_SECRET)
	return strings.clone(string(data), allocator)
}

run_askpass_cli :: proc() -> int {
	pw := take_askpass_secret(context.allocator)
	if len(pw) > 0 {
		fmt.println(pw)
		zero_and_delete(pw)
		return 0
	}
	fmt.eprintln("nullray-askpass: no password available")
	return 1
}
