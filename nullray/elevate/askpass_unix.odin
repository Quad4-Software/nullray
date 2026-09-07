// SPDX-License-Identifier: 0BSD
#+build !windows
/*
Askpass helper script for sudo -A / DOAS_ASKPASS.
*/

package elevate

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:strings"

ensure_askpass_helper :: proc(allocator := context.allocator) -> string {
	sync.mutex_lock(&g_stash_mu)
	defer sync.mutex_unlock(&g_stash_mu)
	if len(g_helper_path) > 0 {
		return strings.clone(g_helper_path, allocator)
	}
	exe := g_self_exe
	if len(exe) == 0 {
		exe = "nullray"
	}
	dir := os.get_env("TMPDIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	}
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, jerr := filepath.join({dir, fmt.tprintf("nullray-askpass-%d", os.get_pid())}, context.temp_allocator)
	if jerr != nil {
		return ""
	}
	script := fmt.aprintf(
		"#!/bin/sh\nexec %q --askpass\n",
		exe,
		allocator = context.temp_allocator,
	)
	if os.write_entire_file(path, transmute([]byte)script) != nil {
		return ""
	}
	_ = os.chmod(path, os.perm(0o755))
	g_helper_path = strings.clone(path)
	return strings.clone(g_helper_path, allocator)
}
