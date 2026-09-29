// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenRouter credits fetch and hide-sensitive toggle.
*/

package app

import "core:os"
import "core:sync"
import "core:strings"
import "core:thread"
import "nullray:constants"
import "nullray:provider"

// Lock-protected snapshot of the credits string for readers on other threads.
app_credits_label :: proc(a: ^App) -> string {
	sync.mutex_lock(&a.credits_mu)
	defer sync.mutex_unlock(&a.credits_mu)
	return strings.clone(a.credits_label)
}

@(private)
app_credits_set :: proc(a: ^App, label: string) {
	sync.mutex_lock(&a.credits_mu)
	delete(a.credits_label)
	a.credits_label = label
	sync.mutex_unlock(&a.credits_mu)
}

app_refresh_credits :: proc(a: ^App) {
	if a.hide_sensitive {
		app_credits_set(a, "")
		return
	}
	if a.credits_busy {
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil || p.id != "openrouter" || len(p.api_key) == 0 {
		app_credits_set(a, "")
		return
	}
	a.credits_busy = true
	args := new(Credits_Job)
	args.app = a
	args.api_key = strings.clone(provider.openrouter_credits_key(p.api_key))
	th := thread.create_and_start_with_data(args, credits_job)
	if th == nil {
		delete(args.api_key)
		free(args)
		a.credits_busy = false
		return
	}
	a.credits_worker = th
}

Credits_Job :: struct {
	app:     ^App,
	api_key: string,
}

@(private)
credits_job :: proc(data: rawptr) {
	args := cast(^Credits_Job)data
	defer {
		delete(args.api_key)
		free(args)
	}
	if args.app.hide_sensitive {
		app_credits_set(args.app, "")
		args.app.credits_busy = false
		args.app.dirty = true
		return
	}
	bal := provider.openrouter_fetch_balance(args.api_key)
	defer delete(bal.err)
	defer delete(bal.label)
	app_credits_set(args.app, provider.openrouter_balance_label(bal))
	args.app.credits_busy = false
	args.app.dirty = true
}

hide_sensitive_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HIDE_SENSITIVE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "hide":
			return true
		case "0", "false", "off", "no", "show":
			return false
		}
	}
	return false
}

app_set_hide_sensitive :: proc(a: ^App, hide: bool) {
	a.hide_sensitive = hide
	if hide {
		os.set_env(constants.ENV_HIDE_SENSITIVE, "1")
		app_credits_set(a, "")
	} else {
		os.unset_env(constants.ENV_HIDE_SENSITIVE)
		app_refresh_credits(a)
	}
	app_refresh_provider_status(a)
	app_mark_dirty(a)
}
