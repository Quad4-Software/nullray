// SPDX-License-Identifier: 0BSD
/*
Wire agent.run_turn into subagent spawn runner.
*/

package agent

import "core:strings"
import "nullray:provider"
import "nullray:subagent"
import "nullray:tools"

child_job_stop_check :: proc(user: rawptr) -> Stop_Kind {
	job := cast(^subagent.Child_Job)user
	if job == nil || job.rt == nil {
		return .None
	}
	if subagent.roster_should_cancel(&job.rt.roster, job.handle_id) {
		return .Cancel
	}
	return .None
}

run_child_turn_impl :: proc(
	prov: ^provider.Provider,
	messages: []provider.Message,
	model: string,
	mode: string,
	max_steps: int,
	tools_reg: rawptr,
	stop_user: rawptr,
	allocator := context.allocator,
) -> subagent.Child_Turn_Result {
	cfg := default_config()
	cfg.max_steps = max_steps
	if m, ok := mode_from_string(mode); ok {
		cfg.mode = m
	}
	cfg.tools_registry = cast(^tools.Registry)tools_reg
	if cfg.tools_registry == nil {
		cfg.tools_registry = tools.registry()
	}
	cfg.user = stop_user
	cfg.stop_check = child_job_stop_check
	cfg.stream = false

	req := Run_Request{
		prov = prov,
		messages = messages,
		tools_enabled = true,
		model = model,
	}
	result := run_turn(req, cfg, allocator)
	out := subagent.Child_Turn_Result{
		ok = result.ok,
		content = strings.clone(result.content, allocator),
		err = strings.clone(result.err, allocator),
		stopped = strings.clone(result.stopped, allocator),
		usage = result.usage,
	}
	provider.destroy_messages(result.messages[:])
	delete(result.messages)
	delete(result.err)
	delete(result.stopped)
	return out
}

register_subagent_runner :: proc() {
	subagent.register_run_child_turn(run_child_turn_impl)
}
