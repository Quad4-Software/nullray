// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-step tool execution, speculate handoff, and elevate stop detection.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:elevate"
import "nullray:hooks"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:store"
import "nullray:tools"

turn_exec_tool_calls :: proc(
	msgs: ^[dynamic]provider.Message,
	cfg_local: Config,
	reg: ^tools.Registry,
	mode_s: string,
	calls: []provider.Tool_Call,
	loop_intervene: bool,
	loop_names: string,
	malformed_left: ^int,
	harness: ^Harness_Metrics,
	allocator := context.allocator,
) -> (elevate_stop: bool, had_writes: bool, result_head: u64) {
	if !loop_intervene && cfg_local.speculate_pool != nil && len(calls) > 0 {
		speculate_submit_prefix(cfg_local.speculate_pool, calls, harness, allocator)
	}
	head_hash := u64(0xcbf29ce484222325)
	head_left := LOOP_RESULT_HEAD_BYTES
	for c, ci in calls {
		if check_stop(cfg_local) == .Cancel {
			tools.speculate_discard_all(cfg_local.speculate_pool)
			break
		}
		emit(cfg_local, .Tool_Start, c.arguments, c.name)
		tool_result, tool_err := "", ""
		if loop_intervene {
			tool_err = fmt.aprintf(
				"Loop detected: repeated tool call pattern (%s). Do NOT retry the same calls. Change approach or wrap up the answer without them.",
				loop_names,
				allocator = allocator,
			)
		} else {
			do_post: bool
			rewrote: bool
			tool_result, tool_err, do_post, rewrote = tool_exec_maybe_speculate(
				cfg_local.speculate_pool,
				reg,
				mode_s,
				c,
				ci,
				harness,
				allocator,
				cfg_local.tool_allow,
			)
			if rewrote {
				emit(cfg_local, .Status, fmt.tprintf("hook rewrote args for %s", c.name))
			}
			if do_post {
				post_payload := tool_result
				if len(tool_err) > 0 {
					post_payload = tool_err
				}
				post := hooks.run(.PostToolUse, c.name, post_payload, allocator)
				if post.blocked {
					delete(tool_result)
					delete(tool_err)
					tool_result = ""
					tool_err = post.message
					post.message = ""
				}
				hooks.result_destroy(&post, allocator)
			}
			// Call-formation failures get a bounded retry nudge; after the
			// per-turn budget the model is told to stop calling tools.
			if kind := malformed_call_class(tool_err); kind != .None {
				retry := malformed_left != nil && malformed_left^ > 0
				if retry {
					malformed_left^ -= 1
				}
				wrapped := malformed_result_text(kind, tool_err, retry, allocator)
				delete(tool_err)
				tool_err = wrapped
			}
		}
		raw := tool_result
		is_err := false
		if len(tool_err) > 0 {
			raw = tool_err
			is_err = true
		}
		result_text := sandbox.redact_secrets(raw, allocator)
		head_hash = loop_result_head_update(head_hash, result_text, &head_left)
		delete(tool_result)
		delete(tool_err)
		store.audit_log_append("tool", c.name, "", "")
		emit(cfg_local, .Tool_Done, result_text, c.name)
		emit(cfg_local, .Tool_Message, result_text, c.name)
		detail := cmd_or_path_from_args(c.name, c.arguments)
		envelope := offload_tool_result(c.name, result_text, detail, is_err || looks_like_tool_error(result_text), harness, allocator)
		trusted_boundary := untrusted_tool_result(envelope, allocator)
		delete(envelope)
		append(msgs, provider.Message{
			role = .Tool,
			content = trusted_boundary,
			tool_call_id = strings.clone(c.id, allocator),
			name = strings.clone(c.name, allocator),
		})
		if elevate.is_nonretryable_elevate_text(result_text) {
			elevate_stop = true
		}
		if t, found := tools.registry_find(reg, c.name); found && t.kind == .Write {
			had_writes = true
		}
		if c.name == "compact_context" {
			n := clear_msgs_tool_results(msgs, 2)
			harness.clear_events += n
		}
		delete(result_text)
	}
	return elevate_stop, had_writes, head_hash
}

turn_mid_prepare :: proc(
	msgs: ^[dynamic]provider.Message,
	cfg: Config,
	prov: ^provider.Provider,
	had_writes: bool,
	harness: ^Harness_Metrics,
) {
	// Mid-turn LID: budget the live window excluding the system prompt.
	// Large AGENTS/tool catalogs must not force prepare every step.
	budget := compact_chars_budget()
	trigger := 0
	if budget > 0 {
		trigger = (budget * 70) / 100
		if trigger < 8_000 {
			trigger = budget
		}
	}
	body_chars := messages_content_chars_excluding_system(msgs[:])
	next := suggest_next_action(had_writes, true, false, 0, body_chars, budget)
	if next == .Compact || (budget > 0 && body_chars > trigger) {
		emit(cfg, .Status, "harness: mid-turn prepare")
		stats: Prepare_Stats
		if cfg.prepare_context != nil {
			stats = cfg.prepare_context(msgs, prov, cfg.user)
		} else {
			stats = prepare_context(msgs, prov)
		}
		if stats.cleared > 0 || stats.compacted || stats.writeback {
			harness.midturn_prepare_events += 1
		}
		harness.clear_events += stats.cleared
		if stats.compacted {
			harness.compact_events += 1
		}
		if stats.writeback {
			harness.writeback_events += 1
		}
	}
}
