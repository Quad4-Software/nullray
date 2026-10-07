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
		description = "Ask the user a question and wait for an answer. options makes it a multiple choice (allow_other=true adds a custom answer), confirm=true makes it yes/no",
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
