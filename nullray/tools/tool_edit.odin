// SPDX-License-Identifier: 0BSD
/*
edit_file tool: read, replace, write with sandbox checks.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:patch"
import "nullray:sandbox"
import "nullray:structure"
import "nullray:subagent"

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
	allow_godfile, aerr := json_arg_bool_string(args_json, "allow_godfile", false, allocator)
	if aerr != "" {
		return "", aerr
	}

	abs := resolve_path(path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, true) {
		return "", strings.clone("path not allowed for write", allocator)
	}
	if lease_err := subagent.check_write_allowed(abs, allocator); len(lease_err) > 0 {
		return "", lease_err
	}

	data, read_err := os.read_entire_file(abs, allocator)
	if read_err != nil {
		return "", fmt.aprintf("read failed: %v", read_err, allocator = allocator)
	}
	defer delete(data)
	if len(data) > constants.MAX_TOOL_FILE_BYTES {
		return "", fmt.aprintf("file exceeds %d bytes", constants.MAX_TOOL_FILE_BYTES, allocator = allocator)
	}

	content := string(data)
	updated, kind, perr2 := patch.apply_replace(content, old_string, new_string, replace_all, allocator)
	if len(perr2) > 0 {
		hint := patch.format_hint(abs, perr2, content, old_string, allocator)
		delete(perr2)
		return "", hint
	}
	defer delete(updated)

	if gate_err := structure.growth_error(
		workspace_root(context.temp_allocator),
		path,
		content,
		updated,
		allow_godfile,
		allocator,
	); len(gate_err) > 0 {
		return "", gate_err
	}
	snapshot_before_write(abs)
	if werr := os.write_entire_file(abs, transmute([]u8)updated); werr != nil {
		return "", fmt.aprintf("write failed: %v", werr, allocator = allocator)
	}
	if kind == .Fuzzy {
		return strings.clone("ok fuzzy", allocator), ""
	}
	return strings.clone("ok", allocator), ""
}
