// SPDX-License-Identifier: 0BSD
package secure

import "core:os"
import "core:path/filepath"
import "core:strings"

audit_deps :: proc(workspace: string, allocator := context.allocator) -> string {
	w: Finding_Writer
	writer_init(&w, allocator)
	check_lock(&w, workspace, "package.json", []string{"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock"})
	check_lock(&w, workspace, "pyproject.toml", []string{"uv.lock", "poetry.lock", "Pipfile.lock"})
	check_lock(&w, workspace, "Cargo.toml", []string{"Cargo.lock"})
	check_lock(&w, workspace, "go.mod", []string{"go.sum"})
	return writer_text(&w)
}

check_lock :: proc(w: ^Finding_Writer, workspace, manifest: string, locks: []string) {
	manifest_path, merr := filepath.join({workspace, manifest}, context.temp_allocator)
	if merr != nil || !regular_file_exists(manifest_path) {
		return
	}
	for lock in locks {
		lock_path, lerr := filepath.join({workspace, lock}, context.temp_allocator)
		if lerr == nil && regular_file_exists(lock_path) {
			return
		}
	}
	finding(w, "warn", "deps", manifest, 0, "dependency manifest has no recognized lock file")
}

regular_file_exists :: proc(path: string) -> bool {
	info, err := os.stat(path, context.temp_allocator)
	return err == nil && info.type == .Regular
}
