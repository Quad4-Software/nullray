// SPDX-License-Identifier: 0BSD
/*
Background prompt improve worker and apply/undo.
*/

package app

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:provider"
import "nullray:session"

@(private)
app_improve_prompt :: proc(a: ^App) {
	if a.session.busy || a.improving {
		return
	}
	draft := strings.trim_space(strings.to_string(a.input))
	if len(draft) == 0 {
		session.session_set_status(&a.session, "type a prompt first, then F2 /improve")
		app_mark_dirty(a)
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil {
		session.session_set_status(&a.session, "no provider")
		return
	}
	a.improving = true
	a.improve_gen += 1
	gen := a.improve_gen
	session.session_set_status(&a.session, "improving prompt...")
	app_mark_dirty(a)
	job := new(Improve_Job)
	job.app = a
	job.gen = gen
	job.draft = strings.clone(draft)
	job.prov = p^
	job.prov.base_url = strings.clone(p.base_url)
	job.prov.api_key = strings.clone(p.api_key)
	job.prov.default_model = strings.clone(p.default_model)
	thread.run_with_data(job, improve_job)
}

Improve_Job :: struct {
	app:   ^App,
	gen:   u64,
	draft: string,
	prov:  provider.Provider,
}

@(private)
improve_job :: proc(data: rawptr) {
	args := cast(^Improve_Job)data
	defer {
		delete(args.draft)
		provider.provider_destroy(&args.prov)
		free(args)
	}
	improved, err := agent.improve_prompt(&args.prov, args.draft)
	a := args.app
	sync.mutex_lock(&a.improve_pending_mu)
	delete(a.improve_pending_text)
	delete(a.improve_pending_err)
	a.improve_pending_text = ""
	a.improve_pending_err = ""
	if len(err) > 0 {
		a.improve_pending_err = strings.clone(err)
		delete(err)
		delete(improved)
	} else {
		a.improve_pending_text = improved
		a.improve_pending_err = ""
	}
	a.improve_pending_gen = args.gen
	a.improve_pending = true
	sync.mutex_unlock(&a.improve_pending_mu)
}

app_apply_improve_pending :: proc(a: ^App) -> bool {
	sync.mutex_lock(&a.improve_pending_mu)
	if !a.improve_pending {
		sync.mutex_unlock(&a.improve_pending_mu)
		return false
	}
	gen := a.improve_pending_gen
	text := a.improve_pending_text
	err := a.improve_pending_err
	a.improve_pending_text = ""
	a.improve_pending_err = ""
	a.improve_pending = false
	sync.mutex_unlock(&a.improve_pending_mu)

	a.improving = false
	if gen != a.improve_gen {
		delete(text)
		delete(err)
		return true
	}
	if len(err) > 0 {
		session.session_set_status(&a.session, fmt.tprintf("improve failed: %s", err))
		delete(err)
		delete(text)
		app_mark_dirty(a)
		return true
	}
	draft := strings.to_string(a.input)
	delete(a.improve_undo)
	a.improve_undo = strings.clone(draft)
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, text)
	a.cursor = len(text)
	delete(text)
	session.session_set_status(&a.session, "prompt improved (ctrl-z undo, enter to send)")
	app_mark_dirty(a)
	return true
}

@(private)
app_undo_improve :: proc(a: ^App) {
	if len(a.improve_undo) == 0 {
		session.session_set_status(&a.session, "nothing to undo")
		app_mark_dirty(a)
		return
	}
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, a.improve_undo)
	a.cursor = len(a.improve_undo)
	delete(a.improve_undo)
	a.improve_undo = ""
	session.session_set_status(&a.session, "undid prompt improve")
	app_mark_dirty(a)
}
