// SPDX-License-Identifier: 0BSD
/*
Child job worker and subagent preamble builders.
*/

package subagent

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:store"

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
	for h in job.spec.path_hints {
		delete(h)
	}
	delete(job.spec.path_hints)
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

	if len(job.workspace) > 0 {
		sandbox.workspace_override_set(job.workspace)
	}
	defer sandbox.workspace_override_clear()

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
	if is_locate_type(job.spec.subagent_type) {
		// Heap-owned: cites_destroy must match parse allocator. roster_finish clones.
		formatted := format_locate_summary(summary, context.allocator)
		defer delete(formatted)
		summary = formatted
	}
	if len(summary) > constants.MAX_CHILD_RESULT_CHARS {
		summary = summary[:constants.MAX_CHILD_RESULT_CHARS]
	}
	failed := !result.ok || result.stopped == "cancelled"
	escalate := strings.contains(strings.to_lower(summary, context.temp_allocator), "escalate:")
	roster_finish(&job.rt.roster, job.handle_id, summary, escalate, failed)
	lease_release_agent(&job.rt.leases, job.handle_id)

	if store.usage_persist_enabled(job.rt.session_persist) && len(job.rt.session_path) > 0 {
		path := job.rt.session_path
		if !job.rt.session_persist {
			path = store.ephemeral_usage_path(filepath.stem(job.rt.session_path), context.temp_allocator)
		}
		tt := result.usage.total_tokens
		if tt == 0 {
			tt = result.usage.prompt_tokens + result.usage.completion_tokens
		}
		runtime_add_child_tokens(job.rt, tt)
		_ = store.append_turn_metrics(path, store.Turn_Metrics{
			model = job.prov.default_model,
			agent_id = job.handle_id,
			prompt_tokens = result.usage.prompt_tokens,
			completion_tokens = result.usage.completion_tokens,
			total_tokens = tt,
			reasoning_tokens = result.usage.reasoning_tokens,
			cost_usd = result.usage.cost_usd,
			cost_known = result.usage.cost_known,
			stopped = result.stopped,
		})
	} else {
		tt := result.usage.total_tokens
		if tt == 0 {
			tt = result.usage.prompt_tokens + result.usage.completion_tokens
		}
		runtime_add_child_tokens(job.rt, tt)
	}

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

build_locate_preamble :: proc(rt: ^Runtime, id: string, parent_id: string, allocator := context.allocator) -> string {
	_ = rt
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "You are a nullray locate subagent.\n")
	fmt.sbprintf(&b, "Your id: %s\nParent: %s\n", id, parent_id)
	strings.write_string(&b, "Mission: find the smallest useful set of code spans for the parent query.\n")
	strings.write_string(&b, "Tools: repo_map, glob_files, grep_files, read_file, list_dir only.\n")
	strings.write_string(&b, "Prefer precision over recall. Prefer fewer spans.\n")
	strings.write_string(&b, "Do not edit files. Do not publish knowledge. Do not spawn task.\n")
	strings.write_string(&b, "Final reply must be a CITES block:\n")
	strings.write_string(&b, "CITES: N\npath/relative:start-end\n")
	strings.write_string(&b, "or CITES: none when nothing relevant is found.\n")
	strings.write_string(&b, "Paths are workspace-relative. Optional single line path:N means N-N.\n")
	out := strings.to_string(b)
	if len(out) > constants.MAX_COORD_PREAMBLE_CHARS {
		trimmed := strings.clone(out[:constants.MAX_COORD_PREAMBLE_CHARS], allocator)
		delete(out)
		return trimmed
	}
	return out
}
