// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Opt-in toolshim (NULLRAY_TOOLSHIM): when the model answers with text that
looks like an attempted tool call but salvage produced none, one cheap side
chat converts the text into a validated provider.Tool_Call that rejoins the
normal call flow.
*/

package agent

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

// At most this many shim conversions are attempted per turn.
TOOLSHIM_MAX_PER_TURN :: 2
// Shim output only needs one small JSON object.
TOOLSHIM_MAX_TOKENS :: 512

/*
Read NULLRAY_TOOLSHIM fresh. Unset, 0, off, false, no, or disabled turns the
shim off. 1, on, true, or yes enables it with the request model. Any other
value is taken as the shim model id. The returned model borrows the env
lookup or req_model; do not free it.
*/
toolshim_model :: proc(req_model: string) -> (model: string, enabled: bool) {
	v, ok := os.lookup_env(constants.ENV_TOOLSHIM, context.temp_allocator)
	if !ok {
		return "", false
	}
	raw := strings.to_lower(strings.trim_space(v), context.temp_allocator)
	switch raw {
	case "", "0", "false", "no", "off", "disable", "disabled":
		return "", false
	case "1", "true", "yes", "on", "enable", "enabled":
		return req_model, true
	}
	return strings.trim_space(v), true
}

/*
Cheap heuristic: does assistant text look like a failed tool call? True
when the text carries a JSON-ish call object marker or names a registered
tool. Runs only when salvage already found no calls, so false positives
cost one small shim call at worst.
*/
shim_text_looks_toolish :: proc(content: string, reg: ^tools.Registry) -> bool {
	if len(content) == 0 {
		return false
	}
	if strings.contains(content, "{") {
		keys := [4]string{`"name"`, `"function"`, `"tool_call"`, `"arguments"`}
		for key in keys {
			if strings.contains(content, key) {
				return true
			}
		}
	}
	if reg != nil {
		for t in reg.tools {
			if len(t.name) >= 3 && strings.contains(content, t.name) {
				return true
			}
		}
	}
	return false
}

// Names and kinds offered to the shim prompt, gated like the real catalog.
toolshim_tool_list :: proc(reg: ^tools.Registry, mode_s: string, allow: []string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if reg == nil {
		return strings.to_string(b)
	}
	for t in reg.tools {
		if ok, _ := tools.tool_kind_allowed(reg, t.name, mode_s, allow); !ok {
			continue
		}
		kind := "read"
		switch t.kind {
		case .Write:
			kind = "write"
		case .Shell:
			kind = "shell"
		case .Mcp:
			kind = "mcp"
		case .Read:
		}
		fmt.sbprintf(&b, "%s (%s)\n", t.name, kind)
	}
	return strings.to_string(b)
}

/*
Return the first balanced {...} span in text. Brace counting is string and
escape aware so quotes or braces inside string values do not fool the walk.
The first-to-last-brace slice this replaces breaks whenever the shim emits
two objects or a trailing '}' in prose.
*/
@(private)
shim_first_json_object :: proc(text: string) -> (span: string, ok: bool) {
	start := strings.index_byte(text, '{')
	if start < 0 {
		return "", false
	}
	depth := 0
	in_str := false
	escaped := false
	for i in start ..< len(text) {
		c := text[i]
		if in_str {
			if escaped {
				escaped = false
			} else if c == '\\' {
				escaped = true
			} else if c == '"' {
				in_str = false
			}
			continue
		}
		switch c {
		case '"':
			in_str = true
		case '{':
			depth += 1
		case '}':
			depth -= 1
			if depth == 0 {
				return text[start:i + 1], true
			}
		case:
		}
	}
	return "", false
}

/*
Extract one JSON object from shim output and validate it into a Tool_Call.
The name must resolve in the registry (normalization applied, mcp: prefix
accepted) and arguments re-encode as canonical JSON.
*/
toolshim_parse_call :: proc(
	text: string,
	reg: ^tools.Registry,
	seq: int,
	allocator := context.allocator,
) -> (call: provider.Tool_Call, ok: bool) {
	span, found := shim_first_json_object(text)
	if !found {
		return call, false
	}
	doc, perr := json.parse_string(span, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return call, false
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return call, false
	}
	name := ""
	name_keys := [3]string{"name", "function", "tool"}
	for key in name_keys {
		v, found := obj[key]
		if !found {
			continue
		}
		// OpenAI style: "function": {"name": ..., "arguments": ...}
		if inner, is_inner := v.(json.Object); is_inner && key == "function" {
			if nv, nok := inner["name"].(json.String); nok {
				name = string(nv)
			}
			if av, aok := inner["arguments"]; aok {
				if _, has_args := obj["arguments"]; !has_args {
					obj["arguments"] = av
				}
			}
			break
		}
		if s, is_s := v.(json.String); is_s && len(s) > 0 {
			name = string(s)
			break
		}
	}
	if len(name) == 0 {
		return call, false
	}
	resolved := name
	if _, found := tools.registry_find(reg, resolved); !found {
		norm := tools.normalize_tool_name(name, context.temp_allocator)
		if _, nfound := tools.registry_find(reg, norm); nfound {
			resolved = norm
		} else if !strings.has_prefix(name, "mcp:") {
			return call, false
		}
	}
	args := "{}"
	raw_args, has_args := obj["arguments"]
	if !has_args {
		raw_args, has_args = obj["parameters"]
	}
	if !has_args {
		raw_args, has_args = obj["args"]
	}
	if has_args {
		#partial switch v in raw_args {
		case json.String:
			inner := strings.trim_space(string(v))
			if len(inner) > 0 {
				args = inner
			}
		case:
			if b, merr := json.marshal(v, allocator = context.temp_allocator); merr == nil {
				args = string(b)
			}
		}
	}
	// Re-validate: args must be a JSON object for the dispatch path.
	check, cerr := json.parse_string(args, .JSON, allocator = context.temp_allocator)
	if cerr != .None {
		return call, false
	}
	if _, arg_obj := check.(json.Object); !arg_obj {
		args = fmt.aprintf(`{{"_raw":%s}}`, args, allocator = context.temp_allocator)
	}
	call.id = fmt.aprintf("shim-%d", seq, allocator = allocator)
	call.name = strings.clone(resolved, allocator)
	call.arguments = strings.clone(args, allocator)
	return call, true
}

/*
One non-streamed side chat asking the shim model to convert toolish text
into a call. Returns an owned Tool_Call on success; usage reports the shim
call's token spend for fold-in by the caller.
*/
toolshim_convert :: proc(
	prov: ^provider.Provider,
	model: string,
	content: string,
	reg: ^tools.Registry,
	mode_s: string,
	allow: []string,
	seq: int,
	allocator := context.allocator,
) -> (call: provider.Tool_Call, ok: bool, usage: provider.Usage) {
	if prov == nil || prov.chat == nil {
		return call, false, usage
	}
	list := toolshim_tool_list(reg, mode_s, allow, context.temp_allocator)
	system := fmt.aprintf(
		`Convert the intended tool call below into a single function call JSON {"name":"<tool>","arguments":{...}} choosing only from these tools:`+
		"\n%sRespond with only the JSON object.",
		list,
		allocator = context.temp_allocator,
	)
	user := content
	if len(user) > 4000 {
		user = user[:4000]
	}
	msgs := []provider.Message{
		{role = .System, content = system},
		{role = .User, content = user},
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = TOOLSHIM_MAX_TOKENS,
	}
	res := prov.chat(prov, req, context.temp_allocator)
	if !res.ok {
		provider.destroy_chat_response(&res)
		return call, false, usage
	}
	usage = res.usage
	call, ok = toolshim_parse_call(res.content, reg, seq, allocator)
	provider.destroy_chat_response(&res)
	return call, ok, usage
}

/*
One shim attempt at the turn-loop call site: converts toolish text into an
owned single-call slice and folds the side-chat spend into usage. Returns
nil calls when conversion fails so the caller takes the normal no-tool path.
*/
turn_toolshim_attempt :: proc(
	prov: ^provider.Provider,
	model: string,
	content: string,
	reg: ^tools.Registry,
	mode_s: string,
	allow: []string,
	seq: int,
	usage: ^provider.Usage,
	saw_cost: ^bool,
	cost_all_known: ^bool,
	allocator := context.allocator,
) -> (calls: []provider.Tool_Call, converted: bool) {
	call, ok, su := toolshim_convert(prov, model, content, reg, mode_s, allow, seq, allocator)
	if usage != nil {
		usage.prompt_tokens += su.prompt_tokens
		usage.completion_tokens += su.completion_tokens
		usage.total_tokens += su.total_tokens
		shim_tokens := su.prompt_tokens + su.completion_tokens + su.total_tokens
		if su.cost_known {
			usage.cost_usd += su.cost_usd
			if saw_cost != nil {
				saw_cost^ = true
			}
		} else if shim_tokens > 0 && cost_all_known != nil {
			cost_all_known^ = false
		}
	}
	if !ok {
		return nil, false
	}
	calls = make([]provider.Tool_Call, 1, allocator)
	calls[0] = call
	return calls, true
}
