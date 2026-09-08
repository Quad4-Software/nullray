// SPDX-License-Identifier: 0BSD
/*
Per-turn usage JSONL next to session transcripts.
*/

package store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Turn_Metrics :: struct {
	ts:                 i64,
	turn:               int,
	model:              string,
	agent_id:           string,
	prompt_tokens:      int,
	completion_tokens:  int,
	total_tokens:       int,
	reasoning_tokens:   int,
	input_chars:        int,
	cost_usd:           f64,
	cost_known:         bool,
	stopped:            string,
	harness_calls:      int,
	harness_peak_chars: int,
	harness_stubbed:    int,
	harness_artifacts:  int,
	harness_clear:      int,
	harness_compact:    int,
	harness_midturn:    int,
	harness_writeback:  int,
}

Session_Metrics :: struct {
	turns:                 int,
	prompt_tokens:         int,
	completion_tokens:     int,
	total_tokens:          int,
	reasoning_tokens:      int,
	cost_usd:              f64,
	cost_known:            bool,
	peak_input_chars:      int,
	last_input_chars:      int,
	subagent_total_tokens: int,
	provider:              string,
	model:                 string,
}

@(private)
g_usage_mu: sync.Mutex

usage_path_for :: proc(session_jsonl_path: string, allocator := context.allocator) -> string {
	if strings.has_suffix(session_jsonl_path, ".jsonl") {
		base := session_jsonl_path[:len(session_jsonl_path) - len(".jsonl")]
		return fmt.aprintf("%s.usage.jsonl", base, allocator = allocator)
	}
	return fmt.aprintf("%s.usage.jsonl", session_jsonl_path, allocator = allocator)
}

usage_persist_enabled :: proc(session_persist: bool) -> bool {
	if v, ok := os.lookup_env(constants.ENV_USAGE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable":
			return false
		}
	}
	if session_persist {
		return true
	}
	if v, ok := os.lookup_env(constants.ENV_USAGE_PERSIST, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

usage_include_subagents :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_USAGE_INCLUDE_SUBAGENTS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "exclude":
			return false
		}
	}
	return true
}

ephemeral_usage_path :: proc(stamp: string, allocator := context.allocator) -> string {
	ws := ""
	if st := sandbox.state(); st != nil {
		ws = st.workspace
	}
	if len(ws) == 0 {
		ws = "."
	}
	dir, _ := filepath.join({ws, ".nullray", "usage"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	safe := sanitize_name(stamp)
	if len(safe) == 0 {
		safe = "ephemeral"
	}
	joined, err := filepath.join({dir, fmt.tprintf("%s.jsonl", safe)}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s.jsonl", dir, safe, allocator = allocator)
	}
	return joined
}

append_turn_metrics :: proc(session_jsonl_path: string, turn: Turn_Metrics) -> bool {
	if len(session_jsonl_path) == 0 {
		return false
	}
	path := usage_path_for(session_jsonl_path, context.temp_allocator)
	ts := turn.ts
	if ts == 0 {
		ts = time.time_to_unix(time.now())
	}
	line := fmt.tprintf(
		`{{"ts":%d,"turn":%d,"model":%q,"agent_id":%q,"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"input_chars":%d,"cost_usd":%.6f,"cost_known":%v,"stopped":%q,"harness_calls":%d,"harness_peak_chars":%d,"harness_stubbed":%d,"harness_artifacts":%d,"harness_clear":%d,"harness_compact":%d,"harness_midturn":%d,"harness_writeback":%d}}`+"\n",
		ts,
		turn.turn,
		turn.model,
		turn.agent_id,
		turn.prompt_tokens,
		turn.completion_tokens,
		turn.total_tokens,
		turn.reasoning_tokens,
		turn.input_chars,
		turn.cost_usd,
		turn.cost_known,
		turn.stopped,
		turn.harness_calls,
		turn.harness_peak_chars,
		turn.harness_stubbed,
		turn.harness_artifacts,
		turn.harness_clear,
		turn.harness_compact,
		turn.harness_midturn,
		turn.harness_writeback,
	)
	sync.mutex_lock(&g_usage_mu)
	defer sync.mutex_unlock(&g_usage_mu)
	f, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if err != nil {
		return false
	}
	defer os.close(f)
	_, werr := os.write_string(f, line)
	return werr == nil
}

load_session_metrics :: proc(session_jsonl_path: string, allocator := context.allocator) -> (m: Session_Metrics, ok: bool) {
	path := usage_path_for(session_jsonl_path, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return {}, false
	}
	cost_all_known := true
	saw_cost := false
	include_kids := usage_include_subagents()
	lines := strings.split_lines(string(data), context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}
		doc, perr := json.parse_string(trimmed, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			continue
		}
		obj, ook := doc.(json.Object)
		if !ook {
			continue
		}
		agent_id := json_string_field(obj, "agent_id")
		is_child := len(agent_id) > 0 && agent_id != "main"
		pt := json_int_field(obj, "prompt_tokens")
		ct := json_int_field(obj, "completion_tokens")
		tt := json_int_field(obj, "total_tokens")
		rt := json_int_field(obj, "reasoning_tokens")
		if tt == 0 {
			tt = pt + ct
		}
		ic := json_int_field(obj, "input_chars")
		ck := json_bool_field(obj, "cost_known")
		cu := json_float_field_default(obj, "cost_usd")
		if is_child {
			m.subagent_total_tokens += tt
			if !include_kids {
				continue
			}
		} else {
			m.turns += 1
		}
		m.prompt_tokens += pt
		m.completion_tokens += ct
		m.total_tokens += tt
		m.reasoning_tokens += rt
		if ic > m.peak_input_chars {
			m.peak_input_chars = ic
		}
		m.last_input_chars = ic
		if model := json_string_field(obj, "model"); len(model) > 0 {
			delete(m.model)
			m.model = strings.clone(model, allocator)
		}
		if ck {
			m.cost_usd += cu
			saw_cost = true
		} else if pt + ct + tt > 0 {
			cost_all_known = false
		}
	}
	m.cost_known = saw_cost && cost_all_known
	return m, m.turns > 0 || m.subagent_total_tokens > 0 || m.total_tokens > 0
}

export_usage_summary :: proc(session_jsonl_path: string, dest_path: string, allocator := context.allocator) -> (ok: bool, err: string) {
	dest := strings.trim_space(dest_path)
	if len(dest) == 0 {
		return false, strings.clone("export needs a path", allocator)
	}
	m, mok := load_session_metrics(session_jsonl_path, context.temp_allocator)
	if !mok {
		return false, strings.clone("no usage data for session", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	fmt.sbprintf(&b, "turns: %d\n", m.turns)
	fmt.sbprintf(&b, "prompt_tokens: %d\n", m.prompt_tokens)
	fmt.sbprintf(&b, "completion_tokens: %d\n", m.completion_tokens)
	fmt.sbprintf(&b, "total_tokens: %d\n", m.total_tokens)
	fmt.sbprintf(&b, "reasoning_tokens: %d\n", m.reasoning_tokens)
	fmt.sbprintf(&b, "peak_input_chars: %d\n", m.peak_input_chars)
	fmt.sbprintf(&b, "last_input_chars: %d\n", m.last_input_chars)
	fmt.sbprintf(&b, "subagent_total_tokens: %d\n", m.subagent_total_tokens)
	if m.cost_known {
		fmt.sbprintf(&b, "cost_usd: %.6f\n", m.cost_usd)
	} else {
		strings.write_string(&b, "cost_usd: unknown\n")
	}
	if len(m.model) > 0 {
		fmt.sbprintf(&b, "model: %s\n", m.model)
	}
	if werr := os.write_entire_file(dest, transmute([]u8)strings.to_string(b)); werr != nil {
		return false, fmt.aprintf("write failed: %v", werr, allocator = allocator)
	}
	src := usage_path_for(session_jsonl_path, context.temp_allocator)
	if os.exists(src) {
		full := fmt.tprintf("%s.jsonl", dest)
		_ = copy_file_bytes(src, full)
	}
	return true, ""
}

@(private)
json_string_field :: proc(obj: json.Object, key: string) -> string {
	v, ok := obj[key]
	if !ok {
		return ""
	}
	s, sok := v.(json.String)
	if !sok {
		return ""
	}
	return string(s)
}

@(private)
json_int_field :: proc(obj: json.Object, key: string) -> int {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	#partial switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	case json.String:
		parsed, pok := strconv.parse_int(string(n))
		if pok {
			return parsed
		}
	}
	return 0
}

@(private)
json_bool_field :: proc(obj: json.Object, key: string) -> bool {
	v, ok := obj[key]
	if !ok {
		return false
	}
	#partial switch b in v {
	case json.Boolean:
		return bool(b)
	case json.String:
		switch strings.to_lower(string(b), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

@(private)
json_float_field_default :: proc(obj: json.Object, key: string) -> f64 {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	#partial switch n in v {
	case json.Float:
		return f64(n)
	case json.Integer:
		return f64(n)
	}
	return 0
}
