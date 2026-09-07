/*
Advisory session file lock so two nullray processes do not share one JSONL.
*/

package store

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

session_lock_path :: proc(session_jsonl: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s.lock", session_jsonl, allocator = allocator)
}

session_try_lock :: proc(session_jsonl: string) -> (ok: bool, holder: string) {
	path := session_lock_path(session_jsonl, context.temp_allocator)
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil && len(data) > 0 {
		lines := strings.split_lines(string(data), context.temp_allocator)
		if len(lines) > 0 {
			pid, pok := strconv.parse_int(strings.trim_space(lines[0]))
			if pok && pid > 0 {
				if pid_alive(pid) && pid != os.get_pid() {
					return false, fmt.tprintf("pid %d", pid)
				}
			}
		}
	}
	body := fmt.tprintf("%d\n", os.get_pid())
	if os.write_entire_file(path, transmute([]u8)body) != nil {
		return false, "write failed"
	}
	return true, ""
}

session_unlock :: proc(session_jsonl: string) {
	path := session_lock_path(session_jsonl, context.temp_allocator)
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil && len(data) > 0 {
		lines := strings.split_lines(string(data), context.temp_allocator)
		if len(lines) > 0 {
			pid, pok := strconv.parse_int(strings.trim_space(lines[0]))
			if pok && pid == os.get_pid() {
				_ = os.remove(path)
			}
		}
	}
}
