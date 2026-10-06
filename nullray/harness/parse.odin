// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Harness config merge: builtins plus harnesses.json from the config dir and
the workspace. Shape is a flat object keyed by id:

  {"id":{"bin":"opencode","argv":["run","{prompt}"],"timeout_sec":300,
         "output":"text","name":"OpenCode"}}

Every field is optional; a missing argv on a new id is skipped. User entries
override builtins by id. The workspace file loads only while the hooks trust
gate passes because it can ship an arbitrary executable path the same way
.nullray/hooks.json ships hook commands.
*/

package harness

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:hooks"
import "nullray:sandbox"

/*
Ordered merge: builtins first, then config dir, then workspace. Returns the
merged list; caller frees with harnesses_destroy.
*/
load_harnesses :: proc(allocator := context.allocator) -> []Harness {
	out := make([dynamic]Harness, 0, allocator)
	index := make(map[string]int, context.temp_allocator)
	add_presets(&out, &index, allocator)

	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	global_path, gerr := filepath.join({cfg, constants.HARNESSES_FILE}, context.temp_allocator)
	if gerr == nil {
		werr := merge_file(&out, &index, global_path, .Config, allocator)
		if len(werr) > 0 {
			delete(werr, context.temp_allocator)
		}
	}

	if hooks.hooks_workspace_trusted() {
		ws := workspace_dir(context.temp_allocator)
		local_path, lerr := filepath.join({ws, ".nullray", constants.HARNESSES_FILE}, context.temp_allocator)
		if lerr == nil && local_path != global_path {
			werr := merge_file(&out, &index, local_path, .Workspace, allocator)
			if len(werr) > 0 {
				delete(werr, context.temp_allocator)
			}
		}
	}
	return out[:]
}

@(private)
add_presets :: proc(out: ^[dynamic]Harness, index: ^map[string]int, allocator := context.allocator) {
	for p in BUILTIN_PRESETS {
		h := harness_from_preset(p, allocator)
		index[strings.clone(h.id, context.temp_allocator)] = len(out)
		append(out, h)
	}
}

@(private)
harness_from_preset :: proc(p: Preset, allocator := context.allocator) -> Harness {
	h: Harness
	h.id = strings.clone(p.id, allocator)
	h.name = strings.clone(p.name, allocator)
	h.bin = strings.clone(p.bin, allocator)
	h.argv = make([dynamic]string, allocator)
	for a in p.argv {
		append(&h.argv, strings.clone(a, allocator))
	}
	h.output = p.mode
	h.timeout_sec = constants.HARNESS_TIMEOUT_SEC
	h.source = .Builtin
	return h
}

/*
Workspace used for .nullray/harnesses.json. Mirrors hooks_workspace_source:
sandbox state workspace, then NULLRAY_WORKSPACE, then the process cwd.
*/
@(private)
workspace_dir :: proc(allocator := context.allocator) -> string {
	if ws := sandbox.workspace_current(); len(ws) > 0 {
		return strings.clone(ws, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

/*
Merge one harnesses.json file into the list. Missing file is not an error.
Malformed JSON returns a message; caller decides whether to surface it.
*/
merge_file :: proc(
	out: ^[dynamic]Harness,
	index: ^map[string]int,
	path: string,
	source: Source,
	allocator := context.allocator,
) -> (err: string) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return ""
	}
	defer delete(data, context.temp_allocator)
	return merge_json(out, index, string(data), source, path, allocator)
}

/*
Parse a flat {id: {...}} object and fold it into the list. Existing ids have
their fields replaced field-wise; new ids append. Entries with a bin that
names no argv and no existing entry are ignored.
*/
merge_json :: proc(
	out: ^[dynamic]Harness,
	index: ^map[string]int,
	text: string,
	source: Source,
	path: string,
	allocator := context.allocator,
) -> (err: string) {
	doc, perr := json.parse_string(text, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return fmt.aprintf("harnesses config %s parse failed: %v", path, perr, allocator = context.temp_allocator)
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return fmt.aprintf("harnesses config %s must be a JSON object", path, allocator = context.temp_allocator)
	}
	for id, val in obj {
		entry, e_ok := val.(json.Object)
		if !e_ok {
			continue
		}
		apply_entry(out, index, id, entry, source, allocator)
	}
	return ""
}

@(private)
apply_entry :: proc(
	out: ^[dynamic]Harness,
	index: ^map[string]int,
	id: string,
	entry: json.Object,
	source: Source,
	allocator := context.allocator,
) {
	clean := strings.trim_space(id)
	if !valid_id(clean) {
		return
	}
	pos, found := index[clean]
	if !found {
		h: Harness
		h.id = strings.clone(clean, allocator)
		h.name = strings.clone(clean, allocator)
		h.argv = make([dynamic]string, allocator)
		h.timeout_sec = constants.HARNESS_TIMEOUT_SEC
		h.output = .Text
		h.source = source
		index[strings.clone(clean, context.temp_allocator)] = len(out)
		append(out, h)
		pos = len(out) - 1
	}
	h := &out[pos]
	h.source = source
	if v, found := entry["bin"]; found {
		if s, s_ok := v.(json.String); s_ok {
			trimmed := strings.trim_space(string(s))
			if len(trimmed) > 0 {
				delete(h.bin, allocator)
				h.bin = strings.clone(trimmed, allocator)
				// A new binary target invalidates a previous detection.
				delete(h.binary, allocator)
				h.binary = ""
			}
		}
	}
	if v, found := entry["name"]; found {
		if s, s_ok := v.(json.String); s_ok {
			trimmed := strings.trim_space(string(s))
			if len(trimmed) > 0 {
				delete(h.name, allocator)
				h.name = strings.clone(trimmed, allocator)
			}
		}
	}
	if arr_v, found := entry["argv"]; found {
		if arr, ok := arr_v.(json.Array); ok {
			argv := make([dynamic]string, allocator)
			bad := false
			for item in arr {
				s, s_ok := item.(json.String)
				if !s_ok {
					bad = true
					break
				}
				append(&argv, strings.clone(string(s), allocator))
			}
			if !bad {
				for a in h.argv {
					delete(a, allocator)
				}
				delete(h.argv)
				h.argv = argv
			} else {
				for a in argv {
					delete(a, allocator)
				}
				delete(argv)
			}
		}
	}
	if v, found := entry["timeout_sec"]; found {
		if n, n_ok := json_int(v); n_ok && n > 0 {
			h.timeout_sec = min(n, constants.HARNESS_MAX_TIMEOUT_SEC)
		}
	}
	if v, found := entry["output"]; found {
		if s, s_ok := v.(json.String); s_ok {
			switch strings.to_lower(strings.trim_space(string(s)), context.temp_allocator) {
			case "json":
				h.output = .Json
			case "text":
				h.output = .Text
			}
		}
	}
}

@(private)
json_int :: proc(v: json.Value) -> (int, bool) {
	#partial switch n in v {
	case json.Integer:
		return int(n), true
	case json.Float:
		return int(n), true
	case json.String:
		if p, ok := strconv.parse_int(string(n)); ok {
			return p, true
		}
	}
	return 0, false
}

/*
Ids name a harness for the tool call and become map keys; keep them a tight
token set so they can never carry path or flag smuggling.
*/
@(private)
valid_id :: proc(id: string) -> bool {
	if len(id) == 0 || len(id) > 64 {
		return false
	}
	for i in 0 ..< len(id) {
		c := id[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.':
		case:
			return false
		}
	}
	return true
}
