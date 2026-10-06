// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Speculative tool handoff helpers for run_turn.
*/

package agent

import "core:strings"

import "nullray:hooks"
import "nullray:memory"
import "nullray:provider"
import "nullray:tools"

speculate_submit_prefix :: proc(
	pool: ^tools.Speculate_Pool,
	calls: []provider.Tool_Call,
	harness: ^Harness_Metrics,
	allocator := context.allocator,
) {
	if pool == nil || len(calls) == 0 {
		return
	}
	names := make([]string, len(calls), context.temp_allocator)
	for c, i in calls {
		names[i] = c.name
	}
	prefix := tools.speculate_leading_prefix_len(names)
	for i in 0 ..< prefix {
		c := calls[i]
		kid := tools.speculate_key_id(c.id, i, allocator)
		if !tools.speculate_has(pool, kid, c.name, c.arguments) {
			if tools.speculate_submit(pool, kid, c.name, c.arguments) && harness != nil {
				harness.speculate_submit += 1
			}
		}
		delete(kid)
	}
}

/*
Run PreToolUse + tools.run, or reuse a speculative hit.
do_post is false when PreToolUse blocked (PostToolUse skipped, same as serial path).
*/
tool_exec_maybe_speculate :: proc(
	pool: ^tools.Speculate_Pool,
	reg: ^tools.Registry,
	mode_s: string,
	c: provider.Tool_Call,
	idx: int,
	harness: ^Harness_Metrics,
	allocator := context.allocator,
	allow: []string = nil,
) -> (tool_result: string, tool_err: string, do_post: bool, rewrote: bool) {
	effective_allow := allow
	if pool != nil && len(pool.tool_allow) > 0 {
		effective_allow = pool.tool_allow
	}
	if pool != nil && tools.speculate_allowlisted(c.name) {
		kid := tools.speculate_key_id(c.id, idx, allocator)
		take := tools.speculate_take(pool, kid, c.name, c.arguments)
		if take.hit {
			delete(kid)
			if harness != nil {
				harness.speculate_hit += 1
				harness.speculate_saved_ms += int(take.duration_ms)
			}
			if recall := memory.recall_for_tool(c.name, c.arguments, allocator); len(recall) > 0 {
				merged := strings.concatenate({take.result, "\n", recall}, allocator)
				delete(take.result, allocator)
				delete(recall, allocator)
				take.result = merged
			}
			return take.result, take.err, !take.blocked_pre, false
		}
		if harness != nil && tools.speculate_hash_miss(pool, kid, c.name, c.arguments) {
			harness.speculate_miss += 1
		}
		delete(kid)
	}

	pre := hooks.run(.PreToolUse, c.name, c.arguments, allocator)
	if !pre.blocked && c.name == "vcs_commit" {
		hooks.result_destroy(&pre, allocator)
		pre = hooks.run(.PreCommit, c.name, c.arguments, allocator)
	}
	if pre.blocked {
		msg := pre.message
		pre.message = ""
		hooks.result_destroy(&pre, allocator)
		return "", msg, false, false
	}
	// A PreToolUse hook may rewrite the call args wholesale via a
	// {"rewrite":{...}} or {"decision":"rewrite","args":{...}} stdout line.
	exec_args := c.arguments
	if len(pre.rewrite_args) > 0 {
		exec_args = pre.rewrite_args
		rewrote = true
	}
	tool_result, tool_err = tools.run(reg, c.name, exec_args, mode_s, allocator, effective_allow)
	hooks.result_destroy(&pre, allocator)
	// Scoped memory lands right after the action that triggered it. The
	// lesson rides the tool result into context for the rest of the turn.
	if recall := memory.recall_for_tool(c.name, c.arguments, allocator); len(recall) > 0 {
		merged := strings.concatenate({tool_result, "\n", recall}, allocator)
		delete(tool_result, allocator)
		delete(recall, allocator)
		tool_result = merged
	}
	return tool_result, tool_err, true, rewrote
}

tool_seal_bridge :: proc(idx: int, id, name, args: string, user: rawptr) {
	ctx := cast(^Delta_Ctx)user
	if ctx == nil || ctx.cfg.speculate_pool == nil {
		return
	}
	if !tools.speculate_allowlisted(name) {
		return
	}
	kid := tools.speculate_key_id(id, idx)
	defer delete(kid)
	if tools.speculate_submit(ctx.cfg.speculate_pool, kid, name, args) {
		// submit counted in mid-stream path via harness when available
		if ctx.harness != nil {
			ctx.harness.speculate_submit += 1
		}
	}
}
