// SPDX-License-Identifier: 0BSD
/*
Session delete, export, and import.
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

copy_file_bytes :: proc(src, dst: string) -> bool {
	data, err := os.read_entire_file(src, context.temp_allocator)
	if err != nil {
		return false
	}
	return os.write_entire_file(dst, data) == nil
}

session_lock_held_by_other :: proc(session_jsonl: string) -> (held: bool, holder: string) {
	path := session_lock_path(session_jsonl, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return false, ""
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	if len(lines) == 0 {
		return false, ""
	}
	pid, pok := strconv.parse_int(strings.trim_space(lines[0]))
	if !pok || pid <= 0 {
		return false, ""
	}
	if pid_alive(pid) && pid != os.get_pid() {
		return true, fmt.tprintf("pid %d", pid)
	}
	return false, ""
}

delete_session :: proc(name: string) -> (ok: bool, err: string) {
	safe := sanitize_name(name)
	path := named_session_path(safe, context.temp_allocator)
	if !os.exists(path) {
		return false, fmt.tprintf("session %s not found", safe)
	}
	if held, holder := session_lock_held_by_other(path); held {
		return false, fmt.tprintf("session locked by %s", holder)
	}
	meta := meta_path_for(path, context.temp_allocator)
	lock := session_lock_path(path, context.temp_allocator)
	usage := usage_path_for(path, context.temp_allocator)
	if os.remove(path) != nil {
		return false, fmt.tprintf("failed to remove %s", path)
	}
	_ = os.remove(meta)
	_ = os.remove(lock)
	_ = os.remove(usage)
	return true, ""
}

export_session :: proc(name: string, dest_dir: string) -> (ok: bool, err: string) {
	dest := strings.trim_space(dest_dir)
	if len(dest) == 0 {
		return false, "export needs a destination directory"
	}
	safe := sanitize_name(name)
	src := named_session_path(safe, context.temp_allocator)
	if !os.exists(src) {
		return false, fmt.tprintf("session %s not found", safe)
	}
	if mkerr := os.make_directory_all(dest); mkerr != nil {
		if info, serr := os.stat(dest, context.temp_allocator); serr != nil || info.type != .Directory {
			return false, fmt.tprintf("cannot create directory %s", dest)
		}
	}
	dst_jsonl, jerr := filepath.join({dest, fmt.tprintf("%s.jsonl", safe)}, context.temp_allocator)
	if jerr != nil {
		dst_jsonl = fmt.tprintf("%s/%s.jsonl", dest, safe)
	}
	if !copy_file_bytes(src, dst_jsonl) {
		return false, fmt.tprintf("failed to copy transcript to %s", dst_jsonl)
	}
	meta_src := meta_path_for(src, context.temp_allocator)
	if os.exists(meta_src) {
		dst_meta, merr := filepath.join({dest, fmt.tprintf("%s.meta.json", safe)}, context.temp_allocator)
		if merr != nil {
			dst_meta = fmt.tprintf("%s/%s.meta.json", dest, safe)
		}
		if !copy_file_bytes(meta_src, dst_meta) {
			return false, fmt.tprintf("failed to copy meta to %s", dst_meta)
		}
	}
	usage_src := usage_path_for(src, context.temp_allocator)
	if os.exists(usage_src) {
		dst_usage, uerr := filepath.join({dest, fmt.tprintf("%s.usage.jsonl", safe)}, context.temp_allocator)
		if uerr != nil {
			dst_usage = fmt.tprintf("%s/%s.usage.jsonl", dest, safe)
		}
		if !copy_file_bytes(usage_src, dst_usage) {
			return false, fmt.tprintf("failed to copy usage to %s", dst_usage)
		}
	}
	return true, ""
}

resolve_import_jsonl :: proc(src_path: string) -> (jsonl: string, err: string) {
	src := strings.trim_space(src_path)
	if len(src) == 0 {
		return "", "import needs a path"
	}
	info, serr := os.stat(src, context.temp_allocator)
	if serr == nil && info.type == .Directory {
		entries, rerr := os.read_directory_by_path(src, -1, context.temp_allocator)
		if rerr != nil {
			return "", fmt.tprintf("cannot read directory %s", src)
		}
		defer os.file_info_slice_delete(entries, context.temp_allocator)
		found := ""
		for e in entries {
			if e.type == .Directory {
				continue
			}
			if strings.has_suffix(e.name, ".jsonl") {
				if len(found) > 0 {
					return "", "directory has more than one .jsonl"
				}
				joined, jerr := filepath.join({src, e.name}, context.temp_allocator)
				if jerr != nil {
					found = fmt.tprintf("%s/%s", src, e.name)
				} else {
					found = joined
				}
			}
		}
		if len(found) == 0 {
			return "", "directory has no .jsonl"
		}
		return found, ""
	}
	if strings.has_suffix(src, ".jsonl") {
		if !os.exists(src) {
			return "", fmt.tprintf("file not found: %s", src)
		}
		return src, ""
	}
	candidate := fmt.tprintf("%s.jsonl", src)
	if os.exists(candidate) {
		return candidate, ""
	}
	if os.exists(src) {
		return src, ""
	}
	return "", fmt.tprintf("file not found: %s", src)
}

import_session :: proc(src_path: string, as_name: string) -> (name: string, ok: bool, err: string) {
	jsonl_src, rerr := resolve_import_jsonl(src_path)
	if len(rerr) > 0 {
		return "", false, rerr
	}
	stem := filepath.stem(jsonl_src)
	want := strings.trim_space(as_name)
	if len(want) == 0 {
		want = stem
	}
	safe := sanitize_name(want)
	dest := named_session_path(safe, context.temp_allocator)
	if os.exists(dest) {
		return "", false, fmt.tprintf("session %s already exists", safe)
	}
	if !copy_file_bytes(jsonl_src, dest) {
		return "", false, fmt.tprintf("failed to copy transcript to %s", dest)
	}
	meta_src := meta_path_for(jsonl_src, context.temp_allocator)
	if os.exists(meta_src) {
		meta_dst := meta_path_for(dest, context.temp_allocator)
		if !copy_file_bytes(meta_src, meta_dst) {
			_ = os.remove(dest)
			return "", false, fmt.tprintf("failed to copy meta to %s", meta_dst)
		}
	}
	usage_src := usage_path_for(jsonl_src, context.temp_allocator)
	if os.exists(usage_src) {
		usage_dst := usage_path_for(dest, context.temp_allocator)
		if !copy_file_bytes(usage_src, usage_dst) {
			_ = os.remove(dest)
			_ = os.remove(meta_path_for(dest, context.temp_allocator))
			return "", false, fmt.tprintf("failed to copy usage to %s", usage_dst)
		}
	}
	return safe, true, ""
}
