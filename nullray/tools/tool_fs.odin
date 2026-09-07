// SPDX-License-Identifier: 0BSD
/*
Built-in filesystem tools: read, write, list.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

tool_read_file :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	path, perr := json_arg_string(args_json, "path", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(path)
	abs := resolve_path(path, allocator)
	defer delete(abs)
	if sandbox.path_is_secret_blocked(abs) {
		return "", strings.clone("secret file blocked (set NULLRAY_SECRETS_ALLOW to grant access)", allocator)
	}
	if !sandbox.path_allowed(sandbox.state(), abs, false) {
		return "", strings.clone("path not allowed for read", allocator)
	}
	data, read_err := os.read_entire_file(abs, allocator)
	if read_err != nil {
		return "", fmt.aprintf("read failed: %v", read_err, allocator = allocator)
	}
	if len(data) > constants.MAX_TOOL_FILE_BYTES {
		delete(data)
		return "", fmt.aprintf("file exceeds %d bytes", constants.MAX_TOOL_FILE_BYTES, allocator = allocator)
	}
	return string(data), ""
}

@(private)
tool_write_file :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	path, perr := json_arg_string(args_json, "path", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(path)
	content, cerr := json_arg_string(args_json, "content", allocator)
	if cerr != "" {
		return "", cerr
	}
	defer delete(content)
	abs := resolve_path(path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, true) {
		return "", strings.clone("path not allowed for write", allocator)
	}
	snapshot_before_write(abs)
	if werr := os.write_entire_file(abs, transmute([]u8)content); werr != nil {
		return "", fmt.aprintf("write failed: %v", werr, allocator = allocator)
	}
	return strings.clone("ok", allocator), ""
}

@(private)
tool_list_dir :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	path, perr := json_arg_string(args_json, "path", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(path)
	abs := resolve_path(path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, false) {
		return "", strings.clone("path not allowed for read", allocator)
	}
	entries, lerr := os.read_all_directory_by_path(abs, allocator)
	if lerr != nil {
		return "", fmt.aprintf("list failed: %v", lerr, allocator = allocator)
	}
	defer os.file_info_slice_delete(entries, allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for e, i in entries {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, e.name)
	}
	return strings.to_string(b), ""
}

