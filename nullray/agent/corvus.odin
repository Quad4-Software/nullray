// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
CORVUS-style synchronized file state (arxiv 2607.22711) layered on the
AgentDiet planning pass. Every read_file and list_dir result is recorded
as (path, line range, content hash). A re-read whose bytes were already
delivered collapses to a stub, a successful write or edit invalidates
earlier reads of that path, and the outgoing request can carry a compact
per-file state block at its last position. Pure functions over the
cloned message list; real session history keeps full fidelity.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

CORVUS_STUB_PREFIX :: "[corvus:"
CORVUS_STATE_MARK :: "[corvus file state]"
CORVUS_STATE_CAP :: 32

Corvus_Stats :: struct {
	stubbed:       int,
	saved_chars:   int,
	state_entries: int,
	state_chars:   int,
}

Corvus_Kind :: enum {
	Read,
	List,
}

Corvus_Stub :: enum {
	None,
	Unchanged,
	Covered,
	Superseded,
}

// One delivered read_file or list_dir tool result.
Corvus_Obs :: struct {
	idx:      int,
	kind:     Corvus_Kind,
	path:     string,
	start:    int, // 1-based first delivered line, reads only
	lines:    []string, // delivered payload lines, reads only
	open_end: bool,     // read ran to end of file
	hash:     u64,
	stub:     Corvus_Stub,
	ref:      int, // msg idx this unchanged stub points at
	kept:     bool, // full content survives in the outgoing request
	stale:    bool, // a tracked mutation lands after this result
}

// One successful mutating tool result (write_file, edit_file, apply_edits).
Corvus_Mut :: struct {
	idx:   int,
	path:  string,
	whash: u64, // fingerprint of the write_file content arg when visible
}

Corvus_State :: struct {
	hash:     u64,
	idx:      int,
	modified: bool,
}

// NULLRAY_CORVUS=0 disables. Default on.
corvus_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_CORVUS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}

corvus_tracks :: proc(name: string) -> bool {
	return name == "read_file" || name == "list_dir"
}

corvus_mutates :: proc(name: string) -> bool {
	switch name {
	case "write_file", "edit_file", "apply_edits", "multi_edit":
		return true
	}
	return false
}

// Successful mutating results start with ok or carry status=ok.
corvus_mut_ok :: proc(m: provider.Message) -> bool {
	if m.is_error {
		return false
	}
	c := strings.trim_left_space(m.content)
	return strings.has_prefix(c, "ok") || strings.contains(c, "status=ok")
}

// read_file results carry a "path ... lines= ..." header line; dedup compares
// the payload only so a rewritten header never hides a content change.
corvus_body :: proc(kind: Corvus_Kind, content: string) -> string {
	if kind == .List {
		return content
	}
	if strings.has_prefix(content, "path ") {
		if nl := strings.index_byte(content, '\n'); nl >= 0 {
			return content[nl + 1:]
		}
		return ""
	}
	return content
}

// Raw string span of a JSON string arg, honoring backslash escapes.
corvus_arg_raw :: proc(args_json, key: string) -> string {
	needle := fmt.tprintf(`"%s"`, key)
	idx := strings.index(args_json, needle)
	if idx < 0 {
		return ""
	}
	rest := args_json[idx + len(needle):]
	colon := strings.index_byte(rest, ':')
	if colon < 0 {
		return ""
	}
	rest = strings.trim_left_space(rest[colon + 1:])
	if len(rest) == 0 || rest[0] != '"' {
		return ""
	}
	for i := 1; i < len(rest); i += 1 {
		if rest[i] == '\\' {
			i += 1
			continue
		}
		if rest[i] == '"' {
			return rest[1:i]
		}
	}
	return ""
}

corvus_arg_int :: proc(args_json, key: string) -> (int, bool) {
	needle := fmt.tprintf(`"%s"`, key)
	idx := strings.index(args_json, needle)
	if idx < 0 {
		return 0, false
	}
	rest := args_json[idx + len(needle):]
	colon := strings.index_byte(rest, ':')
	if colon < 0 {
		return 0, false
	}
	rest = strings.trim_left_space(rest[colon + 1:])
	end := 0
	for end < len(rest) {
		c := rest[end]
		if c != '-' && (c < '0' || c > '9') {
			break
		}
		end += 1
	}
	if end == 0 {
		return 0, false
	}
	return strconv.parse_int(rest[:end])
}

// Every "path" string value in args so apply_edits batches count too. A false
// hit inside quoted content only adds a conservative mutation marker.
corvus_arg_paths :: proc(args_json: string, out: ^[dynamic]string) {
	needle := `"path"`
	from := 0
	for {
		rel := strings.index(args_json[from:], needle)
		if rel < 0 {
			return
		}
		i := from + rel + len(needle)
		rest := args_json[i:]
		colon := strings.index_byte(rest, ':')
		if colon < 0 {
			return
		}
		vstart := i + colon + 1
		for vstart < len(args_json) && args_json[vstart] <= ' ' {
			vstart += 1
		}
		if vstart >= len(args_json) || args_json[vstart] != '"' {
			from = i
			continue
		}
		j := vstart + 1
		for j < len(args_json) {
			if args_json[j] == '\\' {
				j += 2
				continue
			}
			if args_json[j] == '"' {
				break
			}
			j += 1
		}
		if j >= len(args_json) {
			return
		}
		val := args_json[vstart + 1:j]
		if len(val) > 160 {
			val = val[:160]
		}
		if len(val) > 0 {
			append(out, val)
		}
		from = j + 1
	}
}

// A write to a direct child changes a delivered list_dir body.
corvus_direct_child :: proc(dir, p: string) -> bool {
	d := dir
	for len(d) > 0 && d[len(d) - 1] == '/' {
		d = d[:len(d) - 1]
	}
	if len(d) == 0 || !strings.has_prefix(p, d) {
		return false
	}
	rest := p[len(d):]
	if len(rest) < 2 || rest[0] != '/' {
		return false
	}
	return !strings.contains(rest[1:], "/")
}

corvus_mut_affects :: proc(m: Corvus_Mut, o: ^Corvus_Obs) -> bool {
	if m.path == o.path {
		return true
	}
	if o.kind == .List {
		return corvus_direct_child(o.path, m.path)
	}
	return false
}

// Effective coverage of o over e: o kind matches by caller, list results
// cover same-path listings, read ranges use delivered line counts.
corvus_covers :: proc(o, e: ^Corvus_Obs) -> bool {
	if o.kind == .List {
		return true
	}
	o_end := o.start + len(o.lines) - 1
	e_end := e.start + len(e.lines) - 1
	return o.start <= e.start && o_end >= e_end
}

// Every delivered line of the new read must come from a current entry with
// identical text. An open-ended read also requires identical extent so a
// shrunk or grown file can never pass as covered.
corvus_read_covered :: proc(o: ^Corvus_Obs, cur: []int, obs: []Corvus_Obs) -> bool {
	if len(cur) == 0 || len(o.lines) == 0 {
		return false
	}
	max_reach := -1
	for k in 0 ..< len(o.lines) {
		line_no := o.start + k
		matched := false
		for ej in cur {
			e := &obs[ej]
			reach := e.start + len(e.lines) - 1
			if line_no < e.start || line_no > reach {
				continue
			}
			matched = true
			if reach > max_reach {
				max_reach = reach
			}
			if e.lines[line_no - e.start] != o.lines[k] {
				return false
			}
			break
		}
		if !matched {
			return false
		}
	}
	if o.open_end && max_reach != o.start + len(o.lines) - 1 {
		return false
	}
	return true
}
