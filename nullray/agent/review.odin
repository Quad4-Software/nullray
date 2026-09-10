// SPDX-License-Identifier: 0BSD
/*
Diff-aware end-of-turn review, optional style rubric, and local review bot.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

run_review :: proc(
	prov: ^provider.Provider,
	diff_or_summary: string,
	allocator := context.allocator,
) -> (text: string, err: string) {
	if !review_enabled_from_env() {
		return "", ""
	}
	return run_diff_review(prov, diff_or_summary, false, allocator)
}

/*
Always-on local review bot for CLI --review. Uses a larger diff budget and
token cap. force=true skips NULLRAY_REVIEW gate.
*/
run_diff_review :: proc(
	prov: ^provider.Provider,
	diff_or_summary: string,
	force: bool,
	allocator := context.allocator,
) -> (text: string, err: string) {
	if prov == nil || prov.chat == nil {
		return "", strings.clone("no provider", allocator)
	}
	if !force && !review_enabled_from_env() {
		return "", ""
	}
	trimmed := strings.trim_space(diff_or_summary)
	if len(trimmed) == 0 {
		return "", ""
	}
	cap_n := constants.MAX_REVIEW_DIFF_CHARS
	if force {
		cap_n = constants.MAX_REVIEW_BOT_DIFF_CHARS
	}
	truncated := false
	if len(trimmed) > cap_n {
		trimmed = trimmed[:cap_n]
		truncated = true
	}

	model := review_model_from_env(context.temp_allocator)
	if len(model) == 0 {
		model = prov.default_model
	}

	user := trimmed
	if truncated {
		user = fmt.aprintf(
			"%s\n\n[diff truncated to %d chars for review budget]\n",
			trimmed,
			cap_n,
			allocator = context.temp_allocator,
		)
	}

	msgs := []provider.Message{
		{role = .System, content = REVIEW_PROMPT, cacheable = true},
		{role = .User, content = user},
	}
	max_tok := 512
	if force {
		max_tok = constants.DEFAULT_REVIEW_BOT_MAX_TOKENS
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = max_tok,
	}
	res := prov.chat(prov, req, allocator)
	if !res.ok {
		return "", res.err
	}
	out := strings.trim_space(sanitize_model_text(res.content, context.temp_allocator))
	if len(out) == 0 {
		out = strings.trim_space(sanitize_model_text(res.reasoning, context.temp_allocator))
	}
	delete(res.content)
	delete(res.reasoning)
	delete(res.model)
	delete(res.finish_reason)
	provider.destroy_tool_calls(res.tool_calls)
	if len(out) == 0 {
		return "", strings.clone("empty model response", allocator)
	}
	return strings.clone(out, allocator), ""
}

sanitize_model_text :: proc(s: string, allocator := context.allocator) -> string {
	if len(s) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		if r == 0 {
			continue
		}
		strings.write_rune(&b, r)
	}
	return strings.to_string(b)
}

run_rubric :: proc(
	prov: ^provider.Provider,
	diff: string,
	allocator := context.allocator,
) -> (text: string, err: string) {
	if prov == nil || prov.chat == nil {
		return "", strings.clone("no provider", allocator)
	}
	if !rubric_enabled_from_env() {
		return "", ""
	}
	trimmed := strings.trim_space(diff)
	if len(trimmed) == 0 {
		return "", ""
	}
	if len(trimmed) > constants.MAX_REVIEW_DIFF_CHARS {
		trimmed = trimmed[:constants.MAX_REVIEW_DIFF_CHARS]
	}
	model := review_model_from_env(context.temp_allocator)
	if len(model) == 0 {
		model = prov.default_model
	}
	msgs := []provider.Message{
		{role = .System, content = RUBRIC_PROMPT, cacheable = true},
		{role = .User, content = trimmed},
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = 256,
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
		return "", ""
	}
	return strings.clone(out, allocator), ""
}

/*
Build the user payload for a local review bot run.
*/
review_bot_user_payload :: proc(
	vcs_kind: string,
	scope_label: string,
	diff: string,
	allocator := context.allocator,
) -> string {
	return fmt.aprintf(
		"Local %s review scope: %s\nDo not assume GitHub, GitLab, or any forge.\n\nDIFF:\n%s\n",
		vcs_kind,
		scope_label,
		diff,
		allocator = allocator,
	)
}
