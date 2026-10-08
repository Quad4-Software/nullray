// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Interactive user-prompt tools. ask_question shows text, choice, or confirm
prompts, ask_secret collects API keys and tokens out of band into a named
vault so values never enter tool results or provider messages.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:ask"

ASK_UNAVAILABLE :: "interactive prompt unavailable (no UI channel); proceed with reasonable assumptions and state them"

register_ask_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "ask_question",
		description = "Ask the user a question and wait for an answer. options makes it a multiple choice (allow_other=true adds a custom answer), confirm=true makes it yes/no. For multi-field forms use show_view.",
		schema_json = `{"type":"object","properties":{"question":{"type":"string"},"options":{"type":"array","items":{"type":"string"}},"allow_other":{"type":"string","description":"true or false (default true)"},"confirm":{"type":"string","description":"true for a yes/no prompt"},"timeout_sec":{"type":"string"}},"required":["question"]}`,
		kind = .Read,
		run = tool_ask_question,
	})
	registry_register(r, Tool{
		name = "ask_secret",
		description = "Prompt the user for a secret (API key, token) via a masked input. Stored under name in a vault and bound to env; the value never enters tool results",
		schema_json = `{"type":"object","properties":{"name":{"type":"string","description":"env-style name like OPENAI_API_KEY"},"prompt":{"type":"string"},"set_env":{"type":"string","description":"bind to process env (default true)"},"timeout_sec":{"type":"string"}},"required":["name"]}`,
		kind = .Read,
		run = tool_ask_secret,
	})
	registry_register(r, Tool{
		name = "show_view",
		description = "Show a custom interactive TUI form. schema: title, body, width, height, fg/bg/accent/border colors (#hex or names), emoji bool, placement modal|panel, image, fields, actions (submit|cancel|secondary|script). Panel docks in the side pane. Returns JSON {action,values}. Disabled when NULLRAY_UI_MALLEABLE=0.",
		schema_json = `{"type":"object","properties":{"schema":{"type":"string"},"title":{"type":"string"},"body":{"type":"string"},"width":{"type":"string"},"height":{"type":"string"},"fg":{"type":"string"},"bg":{"type":"string"},"accent":{"type":"string"},"placement":{"type":"string"},"image":{"type":"string"},"emoji":{"type":"string"},"fields":{"type":"array","items":{"type":"object"}},"timeout_sec":{"type":"string"}},"required":[]}`,
		kind = .Read,
		run = tool_show_view,
	})
}

tool_show_view :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if !ui_malleable_enabled() {
		return "", strings.clone("show_view disabled (NULLRAY_UI_MALLEABLE=0)", allocator)
	}
	// Prefer a full schema string; otherwise build one from title/body/fields.
	schema_s, _ := json_arg_string_optional(args_json, "schema", "", allocator)
	defer delete(schema_s)
	src := strings.trim_space(schema_s)
	built := false
	if len(src) == 0 {
		// Compose from top-level keys so models can pass structured args.
		title, _ := json_arg_string_optional(args_json, "title", "View", context.temp_allocator)
		body, _ := json_arg_string_optional(args_json, "body", "", context.temp_allocator)
		placement, _ := json_arg_string_optional(args_json, "placement", "", context.temp_allocator)
		image, _ := json_arg_string_optional(args_json, "image", "", context.temp_allocator)
		fg, _ := json_arg_string_optional(args_json, "fg", "", context.temp_allocator)
		bg, _ := json_arg_string_optional(args_json, "bg", "", context.temp_allocator)
		accent, _ := json_arg_string_optional(args_json, "accent", "", context.temp_allocator)
		width, _ := json_arg_string_optional(args_json, "width", "", context.temp_allocator)
		height, _ := json_arg_string_optional(args_json, "height", "", context.temp_allocator)
		fields_raw := ""
		if fr, ferr := json_arg_raw_object_slice(args_json, "fields"); ferr == "" {
			fields_raw = fr
		}
		actions_raw := ""
		if ar, aerr := json_arg_raw_object_slice(args_json, "actions"); aerr == "" {
			actions_raw = ar
		}
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, `{"title":`)
		write_json_string_tool(&b, title)
		strings.write_string(&b, `,"body":`)
		write_json_string_tool(&b, body)
		if len(placement) > 0 {
			strings.write_string(&b, `,"placement":`)
			write_json_string_tool(&b, placement)
		}
		if len(image) > 0 {
			strings.write_string(&b, `,"image":`)
			write_json_string_tool(&b, image)
		}
		if len(fg) > 0 {
			strings.write_string(&b, `,"fg":`)
			write_json_string_tool(&b, fg)
		}
		if len(bg) > 0 {
			strings.write_string(&b, `,"bg":`)
			write_json_string_tool(&b, bg)
		}
		if len(accent) > 0 {
			strings.write_string(&b, `,"accent":`)
			write_json_string_tool(&b, accent)
		}
		if len(width) > 0 {
			strings.write_string(&b, `,"width":`)
			strings.write_string(&b, width)
		}
		if len(height) > 0 {
			strings.write_string(&b, `,"height":`)
			strings.write_string(&b, height)
		}
		if len(fields_raw) > 0 {
			strings.write_string(&b, `,"fields":`)
			strings.write_string(&b, fields_raw)
		}
		if len(actions_raw) > 0 {
			strings.write_string(&b, `,"actions":`)
			strings.write_string(&b, actions_raw)
		}
		strings.write_byte(&b, '}')
		src = strings.to_string(b)
		built = true
	}
	def, perr := ask.view_parse(src, context.temp_allocator)
	if perr != "" {
		return "", perr
	}
	// Re-encode a cleaned schema so the UI and model share the same shape.
	// view_parse already applied caps and defaults.
	timeout, _ := json_arg_int_optional(args_json, "timeout_sec", ask.VIEW_DEFAULT_TIMEOUT_SEC, allocator)
	if timeout <= 0 {
		timeout = ask.VIEW_DEFAULT_TIMEOUT_SEC
	}
	if timeout > 3600 {
		timeout = 3600
	}
	prompt := def.title
	if len(prompt) == 0 {
		prompt = "View"
	}
	// Pass the original (or built) JSON as the view payload.
	answer, ok, cancelled := ask.request_ex(.View, prompt, nil, false, src, i64(timeout), allocator)
	_ = built
	_ = def
	if cancelled {
		return strings.clone(`{"action":"cancel","values":{},"status":"cancelled"}`, allocator), ""
	}
	if !ok {
		return "", strings.clone(ASK_UNAVAILABLE, allocator)
	}
	// answer is already JSON from the TUI; wrap a soft status if bare.
	if len(strings.trim_space(answer)) == 0 {
		delete(answer)
		return strings.clone(`{"action":"submit","values":{}}`, allocator), ""
	}
	return answer, ""
}

// Pull a raw JSON array substring for key from args (best-effort).
@(private)
json_arg_raw_object_slice :: proc(args_json, key: string) -> (string, string) {
	needle := fmt.tprintf(`"%s"`, key)
	idx := strings.index(args_json, needle)
	if idx < 0 {
		return "", "missing"
	}
	rest := args_json[idx + len(needle):]
	// skip whitespace and colon
	i := 0
	for i < len(rest) && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n' || rest[i] == '\r') {
		i += 1
	}
	if i >= len(rest) || rest[i] != ':' {
		return "", "missing"
	}
	i += 1
	for i < len(rest) && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n' || rest[i] == '\r') {
		i += 1
	}
	if i >= len(rest) || rest[i] != '[' {
		return "", "not array"
	}
	depth := 0
	start := i
	in_str := false
	esc := false
	for i < len(rest) {
		c := rest[i]
		if in_str {
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				in_str = false
			}
			i += 1
			continue
		}
		if c == '"' {
			in_str = true
			i += 1
			continue
		}
		if c == '[' {
			depth += 1
		} else if c == ']' {
			depth -= 1
			if depth == 0 {
				return rest[start:i + 1], ""
			}
		}
		i += 1
	}
	return "", "unclosed"
}

@(private)
write_json_string_tool :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		switch c {
		case '"', '\\':
			strings.write_byte(b, '\\')
			strings.write_byte(b, c)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
}

tool_ask_question :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	question, qerr := json_arg_string(args_json, "question", allocator)
	if qerr != "" {
		return "", qerr
	}
	defer delete(question)
	options, oerr := json_arg_strings_optional(args_json, "options", allocator)
	if oerr != "" {
		return "", oerr
	}
	defer {
		for o in options {
			delete(o)
		}
		delete(options)
	}
	allow_other, _ := json_arg_bool_string(args_json, "allow_other", true)
	timeout, _ := json_arg_int_optional(args_json, "timeout_sec", 600, allocator)

	kind := ask.Kind.Text
	if len(options) > 0 {
		kind = .Choice
	} else if confirm, cerr := json_arg_bool_string(args_json, "confirm", false); cerr == "" && confirm {
		kind = .Confirm
	}

	answer, ok, cancelled := ask.request(kind, question, options, allow_other, i64(timeout), allocator)
	if cancelled {
		return strings.clone("user declined to answer", allocator), ""
	}
	if !ok {
		return "", strings.clone(ASK_UNAVAILABLE, allocator)
	}
	defer delete(answer)
	if kind == .Confirm {
		low := strings.to_lower(strings.trim_space(answer), context.temp_allocator)
		yes := low == "y" || low == "yes" || low == "true" || low == "1"
		return fmt.aprintf("user answered: %s", yes ? "yes" : "no", allocator = allocator), ""
	}
	return fmt.aprintf("user answered: %s", answer, allocator = allocator), ""
}

tool_ask_secret :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	name, nerr := json_arg_string(args_json, "name", allocator)
	if nerr != "" {
		return "", nerr
	}
	defer delete(name)
	trimmed := strings.trim_space(name)
	if len(trimmed) == 0 {
		return "", strings.clone("name required", allocator)
	}
	prompt, _ := json_arg_string_optional(args_json, "prompt", "", allocator)
	defer delete(prompt)
	if len(prompt) == 0 {
		delete(prompt)
		prompt = fmt.aprintf("Enter secret for %s:", trimmed, allocator = allocator)
	}
	set_env, _ := json_arg_bool_string(args_json, "set_env", true)
	timeout, _ := json_arg_int_optional(args_json, "timeout_sec", 600, allocator)

	answer, ok, cancelled := ask.request(.Secret, prompt, nil, true, i64(timeout), allocator)
	if cancelled {
		return strings.clone("user cancelled secret entry", allocator), ""
	}
	if !ok {
		return "", strings.clone(ASK_UNAVAILABLE, allocator)
	}
	if len(strings.trim_space(answer)) == 0 {
		delete(answer)
		return "", strings.clone("empty secret not stored", allocator)
	}
	ask.secret_put(trimmed, answer)
	delete(answer)
	if set_env {
		// Providers and spawned tools read keys from env, bind without echoing.
		_ = ask.secret_bind_env(trimmed)
	}
	return fmt.aprintf("secret stored under %s (value not shown)", trimmed, allocator = allocator), ""
}
