// SPDX-License-Identifier: 0BSD
/*
edit_file tool: read, replace, write with sandbox checks.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

tool_edit_file :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	path, perr := json_arg_string(args_json, "path", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(path)
	old_string, oerr := json_arg_string(args_json, "old_string", allocator)
	if oerr != "" {
		return "", oerr
	}
	defer delete(old_string)
	new_string, nerr := json_arg_string(args_json, "new_string", allocator)
	if nerr != "" {
		return "", nerr
	}
	defer delete(new_string)
	replace_all, rerr := json_arg_bool_string(args_json, "replace_all", false, allocator)
	if rerr != "" {
		return "", rerr
	}

	abs := resolve_path(path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, true) {
		return "", strings.clone("path not allowed for write", allocator)
	}

	snapshot_before_write(abs)
	data, read_err := os.read_entire_file(abs, allocator)
	if read_err != nil {
		return "", fmt.aprintf("read failed: %v", read_err, allocator = allocator)
	}
	defer delete(data)
	if len(data) > constants.MAX_TOOL_FILE_BYTES {
		return "", fmt.aprintf("file exceeds %d bytes", constants.MAX_TOOL_FILE_BYTES, allocator = allocator)
	}

	content := string(data)
	if !strings.contains(content, old_string) {
		return "", strings.clone("old_string not found", allocator)
	}

	updated: string
	if replace_all {
		updated, _ = strings.replace_all(content, old_string, new_string, allocator)
	} else {
		updated, _ = strings.replace(content, old_string, new_string, 1, allocator)
	}
	defer delete(updated)

	if werr := os.write_entire_file(abs, transmute([]u8)updated); werr != nil {
		return "", fmt.aprintf("write failed: %v", werr, allocator = allocator)
	}
	return strings.clone("ok", allocator), ""
}
