// SPDX-License-Identifier: 0BSD
/*
Transcript backups before trim or drop.
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:provider"

backup_dir :: proc(allocator := context.allocator) -> string {
	ensure_session_dir()
	base := session_dir(context.temp_allocator)
	joined, err := filepath.join({base, "backups"}, allocator)
	if err != nil {
		return fmt.aprintf("%s/backups", base, allocator = allocator)
	}
	return joined
}

backup_transcript :: proc(
	session_path: string,
	messages: []provider.Message,
	label: string,
	allocator := context.allocator,
) -> (path: string, ok: bool) {
	dir := backup_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	stem := "session"
	if len(session_path) > 0 {
		base := filepath.base(session_path)
		if strings.has_suffix(base, ".jsonl") {
			stem = base[:len(base) - len(".jsonl")]
		} else if strings.has_suffix(base, ".msgpack") {
			stem = base[:len(base) - len(".msgpack")]
		} else if len(base) > 0 {
			stem = sanitize_name(base)
		}
	}
	tag := strings.trim_space(label)
	if len(tag) == 0 {
		tag = "trim"
	}
	file := fmt.tprintf("%s-%s-%d.jsonl", stem, tag, time.to_unix_seconds(time.now()))
	joined, err := filepath.join({dir, file}, allocator)
	if err != nil {
		return "", false
	}
	if !save_transcript_jsonl(joined, messages) {
		return "", false
	}
	return joined, true
}
