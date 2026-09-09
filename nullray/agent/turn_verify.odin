// SPDX-License-Identifier: 0BSD
/*
Edit-mode verify gates at assistant-done and step-budget exits.
*/

package agent

import "core:fmt"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

Turn_Verify_Outcome :: enum {
	Skipped,
	Ok,
	Continue,
	Failed_Stop,
}

// Opt-in verify when the model stops with no further tool calls after writes.
turn_verify_on_assistant_done :: proc(
	msgs: ^[dynamic]provider.Message,
	cfg: Config,
	reg: ^tools.Registry,
	tools_on: bool,
	usage_sum: provider.Usage,
	verify_fails: ^int,
	harness: Harness_Metrics,
	allocator := context.allocator,
) -> (outcome: Turn_Verify_Outcome, result: Run_Result) {
	if !(tools_on &&
		cfg.mode == .Edit &&
		(result_prefix_had_writes(msgs[:]) || turn_had_writes(msgs[:]))) {
		return .Skipped, {}
	}
	vcmd, voff := resolve_verify_command(cfg.plan_verify, context.temp_allocator)
	if voff || len(vcmd) == 0 {
		return .Skipped, {}
	}
	vargs := fmt.aprintf(`{{"command":%q}}`, vcmd, allocator = context.temp_allocator)
	emit(cfg, .Status, fmt.tprintf("verify: %s", vcmd))
	emit(cfg, .Tool_Start, vargs, "verify")
	vok, vout := run_verify_command(vcmd, reg, allocator)
	tui_out := truncate_bytes(vout, constants.MAX_VERIFY_OUTPUT_BYTES, context.temp_allocator)
	emit(cfg, .Tool_Done, tui_out, "verify")
	if !vok {
		verify_fails^ += 1
		max_fails := verify_max_fails_from_env()
		aid := verify_store_output(vout, allocator)
		if verify_fails^ >= max_fails {
			fail_msg := format_verify_nudge(
				vcmd,
				verify_fails^,
				max_fails,
				vout,
				true,
				allocator,
				aid,
			)
			delete(vout)
			delete(aid)
			emit(cfg, .Status, "verify failed (breaker)")
			append(msgs, provider.Message{role = .User, content = fail_msg})
			harness_log_metrics(harness)
			return .Failed_Stop, Run_Result{
				ok = true,
				messages = msgs^,
				content = fail_msg,
				stopped = owned_stop("verify_failed", allocator),
				usage = usage_sum,
				verify_fail_count = verify_fails^,
				harness = harness,
			}
		}
		nudge := format_verify_nudge(
			vcmd,
			verify_fails^,
			max_fails,
			vout,
			false,
			allocator,
			aid,
		)
		delete(vout)
		delete(aid)
		emit(cfg, .Status, fmt.tprintf("verify failed (%d/%d)", verify_fails^, max_fails))
		append(msgs, provider.Message{role = .User, content = nudge})
		return .Continue, {}
	}
	delete(vout)
	emit(cfg, .Status, "verify ok")
	verify_fails^ = 0
	return .Ok, {}
}

// Verify after the step budget is exhausted when writes occurred.
turn_verify_on_step_budget :: proc(
	msgs: ^[dynamic]provider.Message,
	cfg: Config,
	reg: ^tools.Registry,
	tools_on: bool,
	had_writes: bool,
	last_content: string,
	usage_sum: provider.Usage,
	verify_fails: ^int,
	harness: Harness_Metrics,
	allocator := context.allocator,
) -> (did: bool, result: Run_Result) {
	if !(tools_on &&
		cfg.mode == .Edit &&
		(had_writes || turn_had_writes(msgs[:]))) {
		return false, {}
	}
	vcmd, voff := resolve_verify_command(cfg.plan_verify, context.temp_allocator)
	if voff || len(vcmd) == 0 {
		return false, {}
	}
	vargs := fmt.aprintf(`{{"command":%q}}`, vcmd, allocator = context.temp_allocator)
	emit(cfg, .Status, fmt.tprintf("verify (step budget): %s", vcmd))
	emit(cfg, .Tool_Start, vargs, "verify")
	vok, vout := run_verify_command(vcmd, reg, allocator)
	tui_out := truncate_bytes(vout, constants.MAX_VERIFY_OUTPUT_BYTES, context.temp_allocator)
	emit(cfg, .Tool_Done, tui_out, "verify")
	if vok {
		delete(vout)
		emit(cfg, .Status, "verify ok")
		harness_log_metrics(harness)
		return true, Run_Result{
			ok = true,
			messages = msgs^,
			content = last_content,
			stopped = owned_stop("done", allocator),
			usage = usage_sum,
			verify_fail_count = 0,
			harness = harness,
		}
	}
	verify_fails^ += 1
	aid := verify_store_output(vout, allocator)
	fail_msg := format_verify_nudge(
		vcmd,
		verify_fails^,
		verify_max_fails_from_env(),
		vout,
		true,
		allocator,
		aid,
	)
	delete(vout)
	delete(aid)
	emit(cfg, .Status, "verify failed (step budget)")
	append(msgs, provider.Message{role = .User, content = fail_msg})
	harness_log_metrics(harness)
	return true, Run_Result{
		ok = true,
		messages = msgs^,
		content = fail_msg,
		stopped = owned_stop("verify_failed", allocator),
		usage = usage_sum,
		verify_fail_count = verify_fails^,
		harness = harness,
	}
}
