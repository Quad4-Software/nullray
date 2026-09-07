/*
apply_edits tool: batch search-replace edits and file creates with validate-then-apply.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

MAX_APPLY_EDITS :: 20

@(private)
Pending_Write :: struct {
	abs:     string,
	content: string,
}

@(private)
Pending_Edit :: struct {
	abs:          string,
	old_string:   string,
	new_string:   string,
	replace_all:  bool,
}

@(private)
Pending_File :: struct {
	abs:     string,
	content: string,
}

@(private)
json_object_string :: proc(
	obj: json.Object,
	key: string,
	required: bool,
	allocator := context.allocator,
) -> (value: string, err: string) {
	val, found := obj[key]
	if !found {
		if required {
			return "", fmt.aprintf("missing field: %s", key, allocator = allocator)
		}
		return "", ""
	}
	s, ok := val.(json.String)
	if !ok {
		return "", fmt.aprintf("field %s must be a string", key, allocator = allocator)
	}
	return strings.clone(string(s), allocator), ""
}

@(private)
json_object_bool_string :: proc(obj: json.Object, key: string, default: bool) -> (value: bool, err: string) {
	val, found := obj[key]
	if !found {
		return default, ""
	}
	s, ok := val.(json.String)
	if !ok {
		return default, fmt.tprintf("field %s must be a string", key)
	}
	switch strings.to_lower(string(s), context.temp_allocator) {
	case "true", "1", "yes":
		return true, ""
	case "false", "0", "no":
		return false, ""
	}
	return default, fmt.tprintf("field %s must be \"true\" or \"false\"", key)
}

@(private)
parse_edits_array :: proc(
	arr: json.Array,
	pending: ^[dynamic]Pending_Edit,
	allocator := context.allocator,
) -> string {
	for item in arr {
		obj, ok := item.(json.Object)
		if !ok {
			return strings.clone("each edit must be an object", allocator)
		}
		path, perr := json_object_string(obj, "path", true, allocator)
		if perr != "" {
			return perr
		}
		old_string, oerr := json_object_string(obj, "old_string", true, allocator)
		if oerr != "" {
			delete(path)
			return oerr
		}
		new_string, nerr := json_object_string(obj, "new_string", true, allocator)
		if nerr != "" {
			delete(path)
			delete(old_string)
			return nerr
		}
		replace_all, rerr := json_object_bool_string(obj, "replace_all", false)
		if rerr != "" {
			delete(path)
			delete(old_string)
			delete(new_string)
			return strings.clone(rerr, allocator)
		}
		abs := resolve_path(path, allocator)
		delete(path)
		if !sandbox.path_allowed(sandbox.state(), abs, true) {
			delete(abs)
			delete(old_string)
			delete(new_string)
			return strings.clone("path not allowed for write", allocator)
		}
		append(
			pending,
			Pending_Edit{
				abs = abs,
				old_string = old_string,
				new_string = new_string,
				replace_all = replace_all,
			},
		)
	}
	return ""
}

@(private)
parse_files_array :: proc(
	arr: json.Array,
	pending: ^[dynamic]Pending_File,
	allocator := context.allocator,
) -> string {
	for item in arr {
		obj, ok := item.(json.Object)
		if !ok {
			return strings.clone("each file entry must be an object", allocator)
		}
		path, perr := json_object_string(obj, "path", true, allocator)
		if perr != "" {
			return perr
		}
		content, cerr := json_object_string(obj, "content", true, allocator)
		if cerr != "" {
			delete(path)
			return cerr
		}
		abs := resolve_path(path, allocator)
		delete(path)
		if !sandbox.path_allowed(sandbox.state(), abs, true) {
			delete(abs)
			delete(content)
			return strings.clone("path not allowed for write", allocator)
		}
		append(pending, Pending_File{abs = abs, content = content})
	}
	return ""
}

@(private)
validate_and_stage_edits :: proc(
	edits: []Pending_Edit,
	staged: ^[dynamic]Pending_Write,
	allocator := context.allocator,
) -> string {
	for e in edits {
		data, read_err := os.read_entire_file(e.abs, allocator)
		if read_err != nil {
			return fmt.aprintf("read failed for %s: %v", e.abs, read_err, allocator = allocator)
		}
		if len(data) > constants.MAX_TOOL_FILE_BYTES {
			delete(data)
			return fmt.aprintf("file exceeds %d bytes: %s", constants.MAX_TOOL_FILE_BYTES, e.abs, allocator = allocator)
		}
		content := string(data)
		if !strings.contains(content, e.old_string) {
			delete(data)
			return fmt.aprintf("old_string not found in %s", e.abs, allocator = allocator)
		}
		updated: string
		if e.replace_all {
			updated, _ = strings.replace_all(content, e.old_string, e.new_string, allocator)
		} else {
			updated, _ = strings.replace(content, e.old_string, e.new_string, 1, allocator)
		}
		delete(data)
		append(staged, Pending_Write{abs = strings.clone(e.abs, allocator), content = updated})
	}
	return ""
}

tool_apply_edits :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	doc, parse_err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if parse_err != nil {
		return "", fmt.aprintf("bad tool args JSON: %v", parse_err, allocator = allocator)
	}
	root, ok := doc.(json.Object)
	if !ok {
		return "", strings.clone("tool args must be a JSON object", allocator)
	}

	pending_edits := make([dynamic]Pending_Edit, allocator)
	defer {
		for e in pending_edits {
			delete(e.abs)
			delete(e.old_string)
			delete(e.new_string)
		}
		delete(pending_edits)
	}
	pending_files := make([dynamic]Pending_File, allocator)
	defer {
		for f in pending_files {
			delete(f.abs)
			delete(f.content)
		}
		delete(pending_files)
	}

	edits_v, has_edits := root["edits"]
	files_v, has_files := root["files"]
	if !has_edits && !has_files {
		return "", strings.clone("missing edits or files array", allocator)
	}

	if has_edits {
		edits_arr, edits_ok := edits_v.(json.Array)
		if !edits_ok {
			return "", strings.clone("edits must be an array", allocator)
		}
		if perr := parse_edits_array(edits_arr, &pending_edits, allocator); perr != "" {
			return "", perr
		}
	}
	if has_files {
		files_arr, files_ok := files_v.(json.Array)
		if !files_ok {
			return "", strings.clone("files must be an array", allocator)
		}
		if perr := parse_files_array(files_arr, &pending_files, allocator); perr != "" {
			return "", perr
		}
	}

	total := len(pending_edits) + len(pending_files)
	if total == 0 {
		return "", strings.clone("no edits or files to apply", allocator)
	}
	if total > MAX_APPLY_EDITS {
		return "", fmt.aprintf("at most %d edits or files per call", MAX_APPLY_EDITS, allocator = allocator)
	}

	staged := make([dynamic]Pending_Write, allocator)
	defer {
		for s in staged {
			delete(s.abs)
			delete(s.content)
		}
		delete(staged)
	}

	if verr := validate_and_stage_edits(pending_edits[:], &staged, allocator); verr != "" {
		return "", verr
	}
	for f in pending_files {
		if len(f.content) > constants.MAX_TOOL_FILE_BYTES {
			return "", fmt.aprintf("content exceeds %d bytes: %s", constants.MAX_TOOL_FILE_BYTES, f.abs, allocator = allocator)
		}
		append(&staged, Pending_Write{abs = strings.clone(f.abs, allocator), content = strings.clone(f.content, allocator)})
	}

	for s in staged {
		snapshot_before_write(s.abs)
		if werr := os.write_entire_file(s.abs, transmute([]u8)s.content); werr != nil {
			return "", fmt.aprintf("write failed for %s: %v", s.abs, werr, allocator = allocator)
		}
	}
	return fmt.aprintf("ok applied=%d", total, allocator = allocator), ""
}
