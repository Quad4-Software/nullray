// SPDX-License-Identifier: 0BSD
/*
Slash /status command.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:sandbox"
import "nullray:session"

slash_cmd_status :: proc(a: ^App, args: string) {
	_ = args
	plan := a.session.last_plan_path
	if len(plan) == 0 {
		plan = "(none)"
	}
	vcmd, voff := agent.resolve_verify_command(a.session.plan_verify, context.temp_allocator)
	verify := vcmd
	if voff {
		verify = "off"
	} else if len(verify) == 0 {
		verify = "(default)"
	}
	sandbox_applied := false
	ops_line := "ops=off"
	if sstate := sandbox.state(); sstate != nil {
		sandbox_applied = sstate.applied
		if len(sstate.ops_label) > 0 {
			ops_line = fmt.tprintf("ops=%s", sstate.ops_label)
		}
	}
	char_budget := session.compact_chars_from_env()
	cost_line := "cost=unknown"
	if a.hide_sensitive {
		cost_line = "cost=hidden"
	} else if a.session.session_usage.cost_known {
		cost_line = fmt.tprintf("cost=$%.6f", a.session.session_usage.cost_usd)
	}
	stopped := a.session.last_stopped
	if len(stopped) == 0 {
		stopped = "-"
	}
	plan_step_line := "-"
	if len(a.session.plan_steps) > 0 {
		plan_step_line = fmt.tprintf("%d/%d", a.session.plan_step_index + 1, len(a.session.plan_steps))
		if a.session.plan_step_index >= len(a.session.plan_steps) {
			plan_step_line = fmt.tprintf("done/%d", len(a.session.plan_steps))
		}
	}
	steps_sidecar := a.session.plan_steps_path
	if len(steps_sidecar) == 0 {
		steps_sidecar = "(none)"
	}
	body := fmt.tprintf(
		"mode=%s\nhunt=%s\nsandbox_applied=%v\n%s\nask_simple=%v\nplan_ok=%v\nplan_step=%s\nverify=%s\nfails=%d\nchars=%d/%d\npeak=%d\ntok=%d/%d\n%s\nstopped=%s\nplan=%s\nsteps_sidecar=%s\nview_auto=%v",
		agent.mode_string(a.session.agent_mode),
		agent.hunt_profile_string(agent.hunt_from_env()),
		sandbox_applied,
		ops_line,
		agent.ask_simple_from_env(),
		a.session.plan_contract_ok,
		plan_step_line,
		verify,
		a.session.verify_fail_count,
		a.session.last_input_chars,
		char_budget,
		a.session.peak_input_chars,
		a.session.last_usage.total_tokens,
		a.session.session_usage.total_tokens,
		cost_line,
		stopped,
		plan,
		steps_sidecar,
		a.view_auto,
	)
	delete(a.status_body)
	a.status_body = strings.clone(body)
	a.status_scroll = 0
	a.show_status = true
	app_mark_dirty(a)
}
