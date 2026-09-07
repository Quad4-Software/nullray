// SPDX-License-Identifier: 0BSD
/*
Spawn and run child agent turns via registered run_child_turn hook.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:provider"

Child_Job :: struct {
	rt:         ^Runtime,
	spec:       Spawn_Spec,
	handle_id:  string,
	parent_id:  string,
	prov:       provider.Provider,
	messages:   [dynamic]provider.Message,
	workspace:  string,
}

spawn_child :: proc(
	rt: ^Runtime,
	spec: Spawn_Spec,
	allocator := context.allocator,
) -> (result_text: string, err: string) {
	if rt == nil {
		return "", strings.clone("no subagent runtime", allocator)
	}
	if !runtime_enabled(rt) {
		return "", strings.clone("subagents disabled (NULLRAY_SUBAGENTS=0 or /agents off)", allocator)
	}
	if g_run_child_turn == nil {
		return "", strings.clone("subagent runner not registered", allocator)
	}
	living := roster_living_count(&rt.roster)
	if living >= rt.limits.max {
		return "", fmt.aprintf("subagent cap reached (%d)", rt.limits.max, allocator = allocator)
	}

	parent_id := runtime_current_agent(rt, context.temp_allocator)
	parent_depth := 0
	if d, ok := roster_agent_depth(&rt.roster, parent_id); ok {
		parent_depth = d
	}
	if parent_depth >= rt.limits.depth {
		return "", fmt.aprintf("subagent depth limit (%d)", rt.limits.depth, allocator = allocator)
	}

	type_name := strings.trim_space(spec.subagent_type)
	if len(type_name) == 0 {
		type_name = "explore"
	}
	mode_s, isol, role := builtin_type_defaults(type_name)
	if spec.isolation_set {
		isol = spec.isolation
	}

	model, merr := policy_resolve(role, spec.model, rt.provider != nil ? rt.provider.default_model : "", rt.main_model, allocator)
	if merr != "" {
		return "", merr
	}

	id := len(spec.resume_id) > 0 ? strings.clone(spec.resume_id, allocator) : roster_next_id(&rt.roster, allocator)
	group_id := strings.trim_space(spec.group_id)
	if len(group_id) == 0 {
		group_id = fmt.aprintf("g-%s", id, allocator = context.temp_allocator)
	}

	ws := workspace_dir()
	wt_path := ""
	wt_branch := ""
	if isol == .Worktree {
		info := worktree_create(id, ws, allocator)
		if !info.ok {
			delete(id)
			delete(model)
			return "", info.err
		}
		wt_path = info.path
		wt_branch = info.branch
		ws = info.path
	}

	max_steps := spec.max_steps
	if max_steps <= 0 {
		max_steps = rt.limits.steps
	}
	if max_steps <= 0 {
		max_steps = constants.MAX_AGENT_STEPS / 2
		if max_steps < 8 {
			max_steps = 8
		}
	}

	h := Agent_Handle{
		id = strings.clone(id),
		parent_id = strings.clone(parent_id),
		role = strings.clone(role),
		model = strings.clone(model),
		mode = strings.clone(mode_s),
		isolation = isol,
		workspace_root = strings.clone(ws),
		worktree_path = strings.clone(wt_path),
		worktree_branch = strings.clone(wt_branch),
		status = .Running,
		progress = strings.clone(spec.description),
		group_id = strings.clone(group_id),
		depth = parent_depth + 1,
		max_steps = max_steps,
		max_tokens = spec.max_tokens,
		started_at = time.tick_now(),
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	roster_register(&rt.roster, h)
	roster_group_add(&rt.roster, group_id, id)

	preamble := build_coord_preamble(rt, id, parent_id, allocator)

	user_prompt := strings.clone(spec.prompt, allocator)
	if len(user_prompt) == 0 {
		delete(user_prompt)
		user_prompt = strings.clone(spec.description, allocator)
	}

	job := new(Child_Job)
	job.rt = rt
	job.spec = spec
	job.handle_id = strings.clone(id)
	job.parent_id = strings.clone(parent_id)
	job.workspace = strings.clone(ws)
	job.messages = make([dynamic]provider.Message)
	// Messages take ownership of preamble and user_prompt.
	append(&job.messages, provider.Message{role = .System, content = preamble, cacheable = true})
	append(&job.messages, provider.Message{role = .User, content = user_prompt})

	if rt.provider == nil {
		cleanup_child_job(job)
		free(job)
		delete(id)
		delete(model)
		return "", strings.clone("no provider for subagent", allocator)
	}
	job.prov = provider_clone_basic(rt.provider, model)
	delete(model)

	if spec.background {
		msg := fmt.aprintf("spawned background agent %s group=%s model=%s isolation=%s", id, group_id, job.prov.default_model, isolation_string(isol), allocator = allocator)
		delete(id)
		thread.run_with_data(job, child_job_proc)
		return msg, ""
	}

	saved_id := strings.clone(id)
	delete(id)
	child_job_proc(job)
	sum := ""
	if hh, ok := roster_get(&rt.roster, saved_id, allocator); ok {
		sum = strings.clone(hh.result_summary, allocator)
		if len(sum) > constants.MAX_CHILD_RESULT_CHARS {
			trimmed := strings.clone(sum[:constants.MAX_CHILD_RESULT_CHARS], allocator)
			delete(sum)
			sum = trimmed
		}
		destroy_handle_fields(&hh, allocator)
	}
	delete(saved_id)
	return sum, ""
}

provider_clone_basic :: proc(src: ^provider.Provider, model: string) -> provider.Provider {
	p: provider.Provider
	p.id = src.id
	p.name = src.name
	p.base_url = strings.clone(src.base_url)
	p.api_key = strings.clone(src.api_key)
	p.default_model = strings.clone(model)
	p.chat = src.chat
	p.stream = src.stream
	p.list_models = src.list_models
	p.user_data = src.user_data
	return p
}

cleanup_child_job :: proc(job: ^Child_Job) {
	if job == nil {
		return
	}
	provider.destroy_messages(job.messages[:])
	delete(job.messages)
	provider.provider_destroy(&job.prov)
	delete(job.handle_id)
	delete(job.parent_id)
	delete(job.workspace)
	delete(job.spec.description)
	delete(job.spec.prompt)
	delete(job.spec.subagent_type)
	delete(job.spec.model)
	delete(job.spec.resume_id)
	delete(job.spec.group_id)
}

child_job_proc :: proc(data: rawptr) {
	job := cast(^Child_Job)data
	if job == nil {
		return
	}
	defer {
		cleanup_child_job(job)
		free(job)
	}

	runtime_set_current_agent(job.rt, job.handle_id)
	defer runtime_set_current_agent(job.rt, job.parent_id)

	max_steps, mode, isol, wt_path, hok := roster_handle_snapshot(&job.rt.roster, job.handle_id)
	result := g_run_child_turn(
		&job.prov,
		job.messages[:],
		job.prov.default_model,
		mode,
		max_steps,
		job.rt.tools_reg,
		job,
	)
	summary := result.content
	if len(summary) == 0 {
		summary = result.err
	}
	if len(summary) > constants.MAX_CHILD_RESULT_CHARS {
		summary = summary[:constants.MAX_CHILD_RESULT_CHARS]
	}
	failed := !result.ok || result.stopped == "cancelled"
	escalate := strings.contains(strings.to_lower(summary, context.temp_allocator), "escalate:")
	roster_finish(&job.rt.roster, job.handle_id, summary, escalate, failed)
	lease_release_agent(&job.rt.leases, job.handle_id)

	if hok && isol == .Worktree && len(wt_path) > 0 {
		_ = worktree_remove_if_clean(workspace_dir(), wt_path)
	}

	delete(result.content)
	delete(result.err)
	delete(result.stopped)
}

build_coord_preamble :: proc(rt: ^Runtime, id: string, parent_id: string, allocator := context.allocator) -> string {
	roster_txt := roster_status_text(&rt.roster, context.temp_allocator)
	digest := knowledge_digest(&rt.knowledge, constants.MAX_KNOWLEDGE_DIGEST_CHARS, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "You are a nullray subagent.\n")
	fmt.sbprintf(&b, "Your id: %s\nParent: %s\n", id, parent_id)
	strings.write_string(&b, "Rules: publish findings with knowledge_put. Update agents_progress. Do not git stash. Do not edit paths you do not lease.\n")
	strings.write_string(&b, "Use agents_status / agents_peek / knowledge_* before duplicating work.\n")
	strings.write_string(&b, "Roster:\n")
	strings.write_string(&b, roster_txt)
	strings.write_byte(&b, '\n')
	if len(digest) > 0 {
		strings.write_string(&b, "Knowledge digest:\n")
		strings.write_string(&b, digest)
	}
	out := strings.to_string(b)
	if len(out) > constants.MAX_COORD_PREAMBLE_CHARS {
		trimmed := strings.clone(out[:constants.MAX_COORD_PREAMBLE_CHARS], allocator)
		delete(out)
		return trimmed
	}
	return out
}
