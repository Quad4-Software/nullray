// SPDX-License-Identifier: 0BSD
/*
Finalize nudge when tools finished with empty assistant text.
*/

package agent

import "core:strings"
import "nullray:provider"

FINALIZE_NUDGE :: "Tool results are ready. Give your final answer now. Do not call tools."

turn_append_finalize_nudge :: proc(msgs: ^[dynamic]provider.Message, allocator := context.allocator) {
	append(
		msgs,
		provider.Message{
			role = .User,
			content = strings.clone(FINALIZE_NUDGE, allocator),
		},
	)
}

turn_needs_finalize :: proc(last_content: string, had_tools: bool, finalize_nudged: bool) -> bool {
	return len(strings.trim_space(last_content)) == 0 && had_tools && !finalize_nudged
}

/*
One tool-less chat after the step budget when the model never wrote a final answer.
*/
turn_finalize_after_max_steps :: proc(
	msgs: ^[dynamic]provider.Message,
	req: Run_Request,
	model: string,
	cfg: Config,
	harness: ^Harness_Metrics,
	usage_sum: ^provider.Usage,
	saw_cost: ^bool,
	cost_all_known: ^bool,
	last_content: ^string,
	allocator := context.allocator,
) -> bool {
	turn_append_finalize_nudge(msgs, allocator)
	emit(cfg, .Status, "harness: finalize after max steps")
	prompt_chars := messages_content_chars(msgs[:])
	harness_record_call(harness, prompt_chars)
	fres := single_chat(req.prov, msgs[:], model, "", cfg, harness, allocator)
	if !fres.ok {
		delete(fres.err)
		return false
	}
	usage_sum.prompt_tokens += fres.usage.prompt_tokens
	usage_sum.completion_tokens += fres.usage.completion_tokens
	usage_sum.total_tokens += fres.usage.total_tokens
	usage_sum.reasoning_tokens += fres.usage.reasoning_tokens
	step_tokens := fres.usage.prompt_tokens + fres.usage.completion_tokens + fres.usage.total_tokens
	if fres.usage.cost_known {
		usage_sum.cost_usd += fres.usage.cost_usd
		saw_cost^ = true
	} else if step_tokens > 0 {
		cost_all_known^ = false
	}
	usage_sum.cost_known = saw_cost^ && cost_all_known^
	append(msgs, provider.Message{role = .Assistant, content = fres.content, reasoning = fres.reasoning})
	last_content^ = fres.content
	delete(fres.model)
	delete(fres.err)
	delete(fres.finish_reason)
	provider.destroy_tool_calls(fres.tool_calls)
	return len(strings.trim_space(last_content^)) > 0
}
