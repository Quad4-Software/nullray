// SPDX-License-Identifier: 0BSD
/*
Opt-in prompt improver: short isolated chat, separate model, undo buffer.
*/

package agent

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

IMPROVE_SYSTEM :: `You improve coding-agent prompts. Rewrite the user's draft into a clearer, more actionable prompt for an autonomous coding agent.
Rules:
- Keep the user's intent.
- Be specific about files, constraints, and done criteria when implied.
- Do not answer the task. Output only the improved prompt text.
- No markdown fences. No preamble.`

improve_model_from_env :: proc(fallback: string, allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_IMPROVE_MODEL, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	return strings.clone(fallback, allocator)
}

improve_max_tokens_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_IMPROVE_MAX_TOKENS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 64 && n <= 4096 {
			return n
		}
	}
	return constants.DEFAULT_IMPROVE_MAX_TOKENS
}

/*
Improve draft with a single non-streaming call. No tools, no history.
*/
improve_prompt :: proc(
	prov: ^provider.Provider,
	draft: string,
	allocator := context.allocator,
) -> (improved: string, err: string) {
	if prov == nil || prov.chat == nil {
		return "", strings.clone("no provider", allocator)
	}
	trimmed := strings.trim_space(draft)
	if len(trimmed) == 0 {
		return "", strings.clone("empty prompt", allocator)
	}
	// Cap draft size so improve cannot burn a huge context.
	if len(trimmed) > 4000 {
		trimmed = trimmed[:4000]
	}

	model := improve_model_from_env(prov.default_model, context.temp_allocator)
	msgs := []provider.Message{
		{role = .System, content = IMPROVE_SYSTEM, cacheable = true},
		{role = .User, content = trimmed},
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = improve_max_tokens_from_env(),
	}
	res := prov.chat(prov, req, allocator)
	if !res.ok {
		return "", res.err
	}
	out := strings.trim_space(res.content)
	delete(res.content)
	delete(res.reasoning)
	delete(res.model)
	delete(res.finish_reason)
	provider.destroy_tool_calls(res.tool_calls)
	if len(out) == 0 {
		return "", strings.clone("empty improve response", allocator)
	}
	return strings.clone(out, allocator), ""
}

auto_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_AUTO, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "on", "yes", "yolo":
			return true
		}
	}
	if v, ok := os.lookup_env(constants.ENV_AUTONOMY, context.temp_allocator); ok && v == "1" {
		return true
	}
	return false
}

apply_auto_mode :: proc() {
	if !auto_from_env() {
		return
	}
	os.set_env(constants.ENV_MODE, "edit")
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_CONFIRM, "0")
	os.set_env(constants.ENV_AUTONOMY, "1")
	if _, ok := os.lookup_env(constants.ENV_AGENT_STEPS, context.temp_allocator); !ok {
		os.set_env(constants.ENV_AGENT_STEPS, "40")
	}
}

autonomy_prompt_section :: proc(allocator := context.allocator) -> string {
	if !auto_from_env() {
		return ""
	}
	return strings.clone(
		"## Autonomous mode\n\nYou are running autonomously. Keep going until the task is done or blocked. Prefer tools over asking. After each meaningful change, briefly note progress. If paused, wait for resume context and continue without restarting from scratch.\n",
		allocator,
	)
}