// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash command: /models lists the live provider catalog on a worker thread.
/models policy keeps the approved-model policy view.
*/

package app

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"

Models_Job :: struct {
	app:     ^App,
	sess:    ^session.Session,
	prov:    provider.Provider,
	current: string,
}

slash_cmd_models :: proc(a: ^App, args: string) {
	rest := strings.to_lower(strings.trim_space(args), context.temp_allocator)
	if rest == "policy" {
		text := subagent.policy_list_text(context.temp_allocator)
		session.session_set_status(a.session, text)
		return
	}
	if len(rest) > 0 {
		session.session_set_status(a.session, "usage: /models [policy]")
		return
	}
	if a.models_busy {
		session.session_set_status(a.session, "loading models…")
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil || p.list_models == nil {
		session.session_set_status(a.session, "no provider model list")
		return
	}
	job := new(Models_Job)
	job.app = a
	job.sess = a.session
	job.prov = p^
	job.prov.base_url = strings.clone(p.base_url)
	job.prov.api_key = strings.clone(p.api_key)
	job.prov.default_model = strings.clone(p.default_model)
	job.prov.caps.probed_model = strings.clone(p.caps.probed_model)
	job.prov.caps.parameter_size = strings.clone(p.caps.parameter_size)
	job.current = strings.clone(p.default_model)
	a.models_busy = true
	a.models_sess = a.session
	session.session_set_status(a.session, fmt.tprintf("loading %s models…", p.id))
	app_mark_dirty(a)
	th := thread.create_and_start_with_data(job, models_job)
	if th == nil {
		delete(job.current)
		provider.provider_destroy(&job.prov)
		free(job)
		a.models_busy = false
		a.models_sess = nil
		session.session_set_status(a.session, "models fetch failed to start")
		return
	}
	a.models_worker = th
}

@(private)
models_job :: proc(data: rawptr) {
	job := cast(^Models_Job)data
	defer {
		provider.provider_destroy(&job.prov)
		delete(job.current)
		free(job)
	}
	models, err := job.prov.list_models(&job.prov)
	a := job.app
	sync.mutex_lock(&a.models_pending_mu)
	defer sync.mutex_unlock(&a.models_pending_mu)
	delete(a.models_text)
	delete(a.models_err)
	a.models_text = ""
	a.models_err = ""
	if len(err) > 0 {
		a.models_err = strings.clone(err)
		delete(err)
		provider.destroy_models(models)
	} else {
		a.models_text = models_list_text(&job.prov, job.current, models)
		provider.destroy_models(models)
	}
	a.models_pending = true
	a.dirty = true
}

// Compose the transcript block for the fetched catalog. Runs on the worker,
// owns its builder on the default allocator until the apply step frees it.
@(private)
models_list_text :: proc(p: ^provider.Provider, current: string, models: []provider.Model_Info) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	provider.modelsdev_enrich(p.id, models)
	fmt.sbprintf(&b, "%s (%s) · %d models\n", p.name, p.id, len(models))
	if len(models) == 0 {
		strings.write_string(&b, "(none returned)")
	}
	for m in models {
		mark := " "
		if m.id == current {
			mark = "*"
		}
		fmt.sbprintf(&b, "%s %s", mark, m.id)
		if p.id == "opencode" || p.id == "opencode-go" {
			if tag := provider.opencode_api_label(p.id, m.id); len(tag) > 0 {
				fmt.sbprintf(&b, "  [%s]", tag)
			}
		}
		if m.context_limit > 0 {
			fmt.sbprintf(&b, "  ctx %s", models_ctx_label(m.context_limit))
		}
		if m.has_cost && (m.cost_in > 0 || m.cost_out > 0) {
			fmt.sbprintf(&b, "  $%g/$%g", m.cost_in, m.cost_out)
		}
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "set with /model ID · approval policy: /models policy")
	return strings.to_string(b)
}

@(private)
models_ctx_label :: proc(tokens: int, allocator := context.temp_allocator) -> string {
	if tokens >= 1_000_000 {
		return fmt.aprintf("%.1fM", f64(tokens) / 1_000_000, allocator = allocator)
	}
	if tokens >= 1000 {
		return fmt.aprintf("%dk", tokens / 1000, allocator = allocator)
	}
	return fmt.aprintf("%d", tokens, allocator = allocator)
}

// Drains the pending models result on the UI thread. The target tab may have
// closed while the fetch ran, so drop the result instead of touching freed state.
app_apply_models_pending :: proc(a: ^App) -> bool {
	sync.mutex_lock(&a.models_pending_mu)
	if !a.models_pending {
		sync.mutex_unlock(&a.models_pending_mu)
		return false
	}
	sess := a.models_sess
	text := a.models_text
	err := a.models_err
	a.models_text = ""
	a.models_err = ""
	a.models_pending = false
	a.models_busy = false
	a.models_sess = nil
	sync.mutex_unlock(&a.models_pending_mu)
	defer delete(text)
	defer delete(err)

	if app_tab_active_index(a, sess) < 0 {
		return true
	}
	if len(err) > 0 {
		session.session_set_status(sess, fmt.tprintf("models: %s", err))
		return true
	}
	session.session_push_assistant(sess, text)
	session.session_set_status(sess, "models")
	return true
}
