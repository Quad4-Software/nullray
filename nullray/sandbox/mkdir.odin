// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Landlock-safe mkdir -p.

os.make_directory_all opens every ancestor as a real directory fd to walk
down, which needs directory access on ungranted roots like / and fails with
EACCES once the sandbox applies. This version stats up to the deepest
ancestor that already exists (stat needs no directory rights) and creates
only the missing suffixes with single-level mkdirs, so the only dirs touched
are ones the ruleset actually covers.
*/

package sandbox

import "base:runtime"
import "core:os"
import "core:path/filepath"

mkdir_all :: proc(path: string, perm := os.Permissions_Default_Directory) -> os.Error {
	if len(path) == 0 {
		return .Invalid_Argument
	}
	if os.is_directory(path) {
		return .Exist
	}
	missing: [dynamic]string
	missing = make([dynamic]string, 0, 8, context.temp_allocator)
	cur := path
	for !os.is_directory(cur) {
		append(&missing, cur)
		parent := filepath.dir(cur)
		if len(parent) == 0 || parent == cur {
			break
		}
		cur = parent
	}
	// missing holds leaf-first, create deepest ancestor first.
	for i := len(missing) - 1; i >= 0; i -= 1 {
		err := os.make_directory(missing[i], perm)
		if err != nil && err != .Exist {
			return err
		}
	}
	return nil
}

// Ensure the parent directory of a file path exists.
mkdir_parents :: proc(file_path: string) -> os.Error {
	dir := filepath.dir(file_path)
	if len(dir) == 0 || dir == "." {
		return nil
	}
	return mkdir_all(dir)
}
