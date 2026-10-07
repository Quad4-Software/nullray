// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Unified experience index: one append-only store serving SEER-style stepwise
trajectory recall, Training-Free GRPO distilled experience, ExpeRepair
episodic+semantic memory, and convolve-style stop rules from failed turns.

Each completed turn distills into one JSONL entry: ordered tool names, a
normalized+hashed task signature, an outcome class, and a one-line note.

The workspace store lives at .nullray/experience.jsonl while the workspace
passes the hooks trust gate. An untrusted workspace falls back to a
repo-keyed file under <config dir>/experience/ so content shipped inside a
cloned repo is never injected unread. NULLRAY_EXPERIENCE=0 disables both
recording and recall.
*/

package experience

import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:hooks"
import "nullray:sandbox"

EXP_MAX_ENTRIES :: 2000
EXP_STORE_FILE :: "experience.jsonl"
EXP_DIGEST_FILE :: "experience.md"
EXP_TASK_CHARS :: 160
EXP_NOTE_CHARS :: 120
EXP_MAX_TOOLS :: 32

Exp_Entry :: struct {
	task:    string, // normalized task text head
	sig:     string, // fnv64a hex of the normalized task
	tools:   [dynamic]string, // ordered tool names
	outcome: string, // ok | err | looped | escalated
	note:    string, // one-line result head or failure class
	ts:      i64,
}

Exp_Store :: struct {
	path:   string, // jsonl store path
	dir:    string, // sibling dir holding experience.md
	global: bool,   // true when resolved to the config-dir fallback
}

exp_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_EXPERIENCE, context.temp_allocator); ok {
		low := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		return low != "0" && low != "off" && low != "false" && low != "no"
	}
	return true
}

// Mirror hooks_workspace_files resolution so the trust gate and the store
// always look at the same root.
exp_workspace_root :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

// A trusted (or file-free) workspace keeps its own store. An untrusted one
// falls back to a repo-keyed global file so shipped content stays out.
exp_store :: proc(allocator := context.allocator) -> Exp_Store {
	root := exp_workspace_root(context.temp_allocator)
	ws_dir, _ := filepath.join({root, ".nullray"}, context.temp_allocator)
	if hooks.hooks_workspace_trusted() {
		path, _ := filepath.join({ws_dir, EXP_STORE_FILE}, context.temp_allocator)
		return Exp_Store{
			path = strings.clone(path, allocator),
			dir = strings.clone(ws_dir, allocator),
		}
	}
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	dir, _ := filepath.join({cfg, "experience"}, context.temp_allocator)
	h := hash.fnv64a(transmute([]byte)root)
	name := fmt.tprintf("repo-%x.jsonl", h)
	path, _ := filepath.join({dir, name}, context.temp_allocator)
	return Exp_Store{
		path = strings.clone(path, allocator),
		dir = strings.clone(dir, allocator),
		global = true,
	}
}

exp_digest_path :: proc(allocator := context.allocator) -> string {
	st := exp_store(context.temp_allocator)
	path, jerr := filepath.join({st.dir, EXP_DIGEST_FILE}, allocator)
	if jerr != nil {
		return strings.clone(EXP_DIGEST_FILE, allocator)
	}
	return path
}

exp_load_entries :: proc(allocator := context.allocator) -> [dynamic]Exp_Entry {
	entries := make([dynamic]Exp_Entry, allocator)
	st := exp_store(context.temp_allocator)
	data, rerr := os.read_entire_file(st.path, context.temp_allocator)
	if rerr != nil {
		return entries
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(line)) == 0 {
			continue
		}
		if e, ok := exp_parse_entry(line, allocator); ok {
			append(&entries, e)
		}
	}
	return entries
}

exp_destroy_entries :: proc(entries: ^[dynamic]Exp_Entry, allocator := context.allocator) {
	if entries == nil {
		return
	}
	for e in entries {
		delete(e.task, allocator)
		delete(e.sig, allocator)
		delete(e.outcome, allocator)
		delete(e.note, allocator)
		for name in e.tools {
			delete(name, allocator)
		}
		delete(e.tools)
	}
	delete(entries^)
	entries^ = nil
}

// Append one entry, then enforce the bound by dropping oldest lines.
exp_append_entry :: proc(e: Exp_Entry) -> string {
	if !exp_enabled() {
		return ""
	}
	st := exp_store(context.temp_allocator)
	_ = sandbox.mkdir_all(st.dir)
	line := exp_format_entry(e, context.temp_allocator)
	f, oerr := os.open(st.path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if oerr != nil {
		return fmt.tprintf("experience open failed: %v", oerr)
	}
	_, werr := os.write_string(f, line)
	os.close(f)
	if werr != nil {
		return fmt.tprintf("experience write failed: %v", werr)
	}
	exp_trim_store(st.path)
	return ""
}

@(private)
exp_trim_store :: proc(path: string) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	n := 0
	for l in lines {
		if len(strings.trim_space(l)) > 0 {
			n += 1
		}
	}
	if n <= EXP_MAX_ENTRIES {
		return
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	skip := n - EXP_MAX_ENTRIES
	for l in lines {
		if len(strings.trim_space(l)) == 0 {
			continue
		}
		if skip > 0 {
			skip -= 1
			continue
		}
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	_ = os.write_entire_file(path, transmute([]u8)strings.to_string(b))
}

exp_format_entry :: proc(e: Exp_Entry, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"v":1,"ts":`)
	fmt.sbprintf(&b, "%d", e.ts)
	strings.write_string(&b, `,"sig":`)
	hooks.write_json_string(&b, e.sig)
	strings.write_string(&b, `,"task":`)
	hooks.write_json_string(&b, e.task)
	strings.write_string(&b, `,"tools":[`)
	for name, i in e.tools {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		hooks.write_json_string(&b, name)
	}
	strings.write_string(&b, `],"outcome":`)
	hooks.write_json_string(&b, e.outcome)
	strings.write_string(&b, `,"note":`)
	hooks.write_json_string(&b, e.note)
	strings.write_string(&b, "}\n")
	return strings.to_string(b)
}

@(private)
exp_json_str :: proc(obj: json.Object, key: string, allocator := context.allocator) -> string {
	if v, ok := obj[key]; ok {
		if s, is := v.(json.String); is {
			return strings.clone(string(s), allocator)
		}
	}
	return ""
}

exp_parse_entry :: proc(line: string, allocator := context.allocator) -> (Exp_Entry, bool) {
	doc, err := json.parse_string(line, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return {}, false
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return {}, false
	}
	e: Exp_Entry
	e.tools = make([dynamic]string, allocator)
	e.task = exp_json_str(obj, "task", allocator)
	e.sig = exp_json_str(obj, "sig", allocator)
	e.outcome = exp_json_str(obj, "outcome", allocator)
	e.note = exp_json_str(obj, "note", allocator)
	if raw, found := obj["ts"]; found {
		#partial switch v in raw {
		case json.Integer:
			e.ts = i64(v)
		case json.Float:
			e.ts = i64(v)
		}
	}
	if raw, found := obj["tools"]; found {
		if arr, is := raw.(json.Array); is {
			for item in arr {
				if s, is2 := item.(json.String); is2 {
					append(&e.tools, strings.clone(string(s), allocator))
				}
			}
		}
	}
	if len(e.task) == 0 && len(e.sig) == 0 {
		delete(e.tools)
		delete(e.task)
		delete(e.sig)
		delete(e.outcome)
		delete(e.note)
		return {}, false
	}
	return e, true
}

// Lowercase alnum tokens, everything else collapses to single spaces.
exp_normalize :: proc(text: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	pending_space := false
	for i in 0 ..< len(text) {
		c := text[i]
		ok := false
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			ok = true
		} else if c >= 'A' && c <= 'Z' {
			c += 32
			ok = true
		}
		if !ok {
			pending_space = true
			continue
		}
		if pending_space && strings.builder_len(b) > 0 {
			strings.write_byte(&b, ' ')
		}
		pending_space = false
		strings.write_byte(&b, c)
		if strings.builder_len(b) >= EXP_TASK_CHARS {
			break
		}
	}
	out := strings.to_string(b)
	if len(out) > EXP_TASK_CHARS {
		out = out[:EXP_TASK_CHARS]
	}
	return strings.clone(out, allocator)
}

exp_sig :: proc(task_norm: string, allocator := context.allocator) -> string {
	h := hash.fnv64a(transmute([]byte)task_norm)
	return fmt.aprintf("%x", h, allocator = allocator)
}

exp_one_line :: proc(text: string, cap: int, allocator := context.allocator) -> string {
	flat, _ := strings.replace_all(text, "\n", " ", context.temp_allocator)
	flat, _ = strings.replace_all(flat, "\r", " ", context.temp_allocator)
	flat = strings.trim_space(flat)
	if len(flat) <= cap {
		return strings.clone(flat, allocator)
	}
	return fmt.aprintf("%s...", flat[:cap], allocator = allocator)
}
