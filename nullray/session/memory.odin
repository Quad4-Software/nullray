// SPDX-License-Identifier: 0BSD
/*
Per-process session locks so multiple nullray instances can run together.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

mem_max_chars_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_MEM_MAX_CHARS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 8_000 {
			return n
		}
	}
	return constants.DEFAULT_MEM_MAX_CHARS
}

session_trim_memory :: proc(s: ^Session, max_chars: int) {
	if s == nil || max_chars <= 0 {
		return
	}
	for {
		total := 0
		for m in s.messages {
			total += len(m.content) + len(m.reasoning) + len(m.name)
			for tc in m.tool_calls {
				total += len(tc.name) + len(tc.arguments) + len(tc.id)
			}
		}
		if total <= max_chars {
			return
		}
		if len(s.messages) <= 2 {
			return
		}
		// Prefer dropping older user/assistant pairs; keep recent tool rows longer.
		drop_i := -1
		for m, i in s.messages {
			if m.role == .System {
				continue
			}
			// Keep the last 4 messages intact when possible
			if i >= len(s.messages) - 4 {
				break
			}
			if m.role == .User || (m.role == .Assistant && len(m.tool_calls) == 0) {
				drop_i = i
				break
			}
			if drop_i < 0 {
				drop_i = i
			}
		}
		if drop_i < 0 {
			for m, i in s.messages {
				if m.role != .System {
					drop_i = i
					break
				}
			}
		}
		if drop_i < 0 {
			return
		}
		provider.destroy_message(s.messages[drop_i])
		ordered_remove(&s.messages, drop_i)
	}
}

runtime_dir :: proc(config_dir: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/runtime", config_dir, allocator = allocator)
}

crash_lock_path :: proc(config_dir: string, allocator := context.allocator) -> string {
	dir := runtime_dir(config_dir, context.temp_allocator)
	_ = os.make_directory_all(dir)
	return fmt.aprintf("%s/nullray-%d.lock", dir, os.get_pid(), allocator = allocator)
}

crash_lock_write :: proc(config_dir: string, session_id: string) {
	path := crash_lock_path(config_dir, context.temp_allocator)
	body := fmt.tprintf("%d\n%s\n", os.get_pid(), session_id)
	_ = os.write_entire_file(path, transmute([]u8)body)
}

crash_lock_clear :: proc(config_dir: string) {
	path := crash_lock_path(config_dir, context.temp_allocator)
	_ = os.remove(path)
}

/*
Count runtime locks whose pid is still alive (other nullray instances plus this one).
*/
count_live_agents :: proc(config_dir: string) -> int {
	dir := runtime_dir(config_dir, context.temp_allocator)
	n := 0
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return 0
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for e in entries {
		name := e.name
		if !strings.has_prefix(name, "nullray-") || !strings.has_suffix(name, ".lock") {
			continue
		}
		path, _ := filepath.join({dir, name}, context.temp_allocator)
		data, rerr := os.read_entire_file(path, context.temp_allocator)
		if rerr != nil || len(data) == 0 {
			continue
		}
		lines := strings.split_lines(string(data), context.temp_allocator)
		if len(lines) < 1 {
			continue
		}
		pid, pok := strconv.parse_int(strings.trim_space(lines[0]))
		if pok && process_alive(pid) {
			n += 1
		}
	}
	return n
}

/*
Recover a session only from a dead process lock. Living instances are left alone
so multiple nullray sessions can run at once.
*/
crash_lock_recover :: proc(config_dir: string, allocator := context.allocator) -> (session_id: string, recovered: bool) {
	dir := runtime_dir(config_dir, context.temp_allocator)
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return "", false
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for e in entries {
		name := e.name
		if !strings.has_prefix(name, "nullray-") || !strings.has_suffix(name, ".lock") {
			continue
		}
		path, _ := filepath.join({dir, name}, context.temp_allocator)
		sid, ok := read_dead_lock(path, allocator)
		if ok {
			_ = os.remove(path)
			return sid, true
		}
	}
	return "", false
}

@(private)
read_dead_lock :: proc(path: string, allocator := context.allocator) -> (session_id: string, recovered: bool) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return "", false
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	if len(lines) < 1 {
		return "", false
	}
	pid, perr := strconv.parse_int(strings.trim_space(lines[0]))
	if !perr {
		return "", false
	}
	if process_alive(pid) {
		return "", false
	}
	sid := ""
	if len(lines) >= 2 {
		sid = strings.trim_space(lines[1])
	}
	if len(sid) == 0 {
		return "", false
	}
	return strings.clone(sid, allocator), true
}
