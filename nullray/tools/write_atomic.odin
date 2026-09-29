// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Atomic file writes for edit/write tools: temp file + rename so a crash or
kill mid-write never leaves a truncated file. Existing permission bits are
reapplied to the temp before rename so scripts keep their execute bit.
*/

package tools

import "core:fmt"
import "core:os"
import "nullray:store"

tool_write_atomic :: proc(path: string, data: []u8) -> (err: string) {
	// Capture mode before writing. A new file has none.
	mode: os.Permissions
	have_mode := false
	if fi, serr := os.stat(path, context.temp_allocator); serr == nil {
		mode = fi.mode
		have_mode = true
	}
	tmp := fmt.tprintf("%s.tmp.%d", path, os.get_pid())
	if werr := os.write_entire_file(tmp, data); werr != nil {
		_ = os.remove(tmp)
		return fmt.tprintf("write failed: %v", werr)
	}
	if have_mode {
		_ = os.chmod(tmp, mode)
	}
	if rerr := os.rename(tmp, path); rerr != nil {
		// Windows rename refuses to overwrite an existing target.
		_ = os.remove(path)
		if rerr2 := os.rename(tmp, path); rerr2 != nil {
			_ = os.remove(tmp)
			return fmt.tprintf("write failed: %v", rerr2)
		}
	}
	return ""
}
