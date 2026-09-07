// SPDX-License-Identifier: 0BSD
/*
Optional end-of-turn review pass (NULLRAY_REVIEW). Separate model, short context.
*/

package agent

import "core:strings"
import "nullray:provider"

run_review :: proc(
	prov: ^provider.Provider,
	summary: string,
	allocator := context.allocator,
) -> (text: string, err: string) {
	if prov == nil || prov.chat == nil {
		return "", strings.clone("no provider", allocator)
	}
	if !review_enabled_from_env() {
		return "", ""
	}
	trimmed := strings.trim_space(summary)
	if len(trimmed) == 0 {
		return "", ""
	}
	if len(trimmed) > 6000 {
		trimmed = trimmed[:6000]
	}

	model := review_model_from_env(context.temp_allocator)
	if len(model) == 0 {
		model = prov.default_model
	}

	msgs := []provider.Message{
		{role = .System, content = REVIEW_PROMPT, cacheable = true},
		{role = .User, content = trimmed},
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = 512,
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
