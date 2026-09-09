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
	apply_hunt_role_sampling(&cfg, stop_user)
	job := cast(^subagent.Child_Job)stop_user
	if job != nil && subagent.is_locate_type(job.spec.subagent_type) {
		cfg.tool_allow = tools.LOCATE_TOOL_ALLOW
		cfg.speculate_parallel = subagent.locate_parallel_from_env()
	}
	if job != nil && subagent.is_architect_type(job.spec.subagent_type) {
		cfg.tool_allow = tools.ARCHITECT_TOOL_ALLOW
	}

	req := Run_Request{
		prov = prov,
		messages = messages,
		tools_enabled = true,
		model = model,
	}
	result := run_turn(req, cfg, allocator)
	content := strings.clone(result.content, allocator)
	if job != nil && subagent.is_architect_type(job.spec.subagent_type) {
		formatted := format_architect_summary(result.content, allocator)
		delete(content)
		content = formatted
	}
	out := subagent.Child_Turn_Result{
		ok = result.ok,
		content = content,
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

@(private)
apply_hunt_role_sampling :: proc(cfg: ^Config, stop_user: rawptr) {
	if !hunt_enabled(cfg.hunt) {
		return
	}
	role := ""
	job := cast(^subagent.Child_Job)stop_user
	if job != nil && len(job.spec.subagent_type) > 0 {
		_, _, role = subagent.builtin_type_defaults(job.spec.subagent_type)
	}
	if len(role) == 0 {
		return
	}
	samp: Sampling
	switch strings.to_lower(role, context.temp_allocator) {
	case "explore":
		samp = hunt_preset_sampling(.Explore)
	case "verify", "review":
		samp = hunt_preset_sampling(.Oracle)
	case "edit":
		samp = hunt_preset_sampling(.Balanced)
	case:
		return
	}
	cfg.temperature = samp.temperature
	cfg.top_p = samp.top_p
	cfg.temperature_set = samp.temperature_set
	cfg.top_p_set = samp.top_p_set
}

register_subagent_runner :: proc() {
	subagent.register_run_child_turn(run_child_turn_impl)
}
