// SPDX-License-Identifier: 0BSD
/*
OpenRouter credits fetch and hide-sensitive toggle.
*/

package app

import "core:os"
import "core:strings"
import "core:thread"
import "nullray:constants"
import "nullray:provider"

app_refresh_credits :: proc(a: ^App) {
	if a.hide_sensitive {
		delete(a.credits_label)
		a.credits_label = ""
		return
	}
	if a.credits_busy {
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil || p.id != "openrouter" || len(p.api_key) == 0 {
		delete(a.credits_label)
		a.credits_label = ""
		return
	}
	a.credits_busy = true
	args := new(Credits_Job)
	args.app = a
	args.api_key = strings.clone(provider.openrouter_credits_key(p.api_key))
	thread.run_with_data(args, credits_job)
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
		delete(args.app.credits_label)
		args.app.credits_label = ""
		args.app.credits_busy = false
		args.app.dirty = true
		return
	}
	bal := provider.openrouter_fetch_balance(args.api_key)
	defer delete(bal.err)
	defer delete(bal.label)
	label := provider.openrouter_balance_label(bal)
	delete(args.app.credits_label)
	args.app.credits_label = label
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
		delete(a.credits_label)
		a.credits_label = ""
	} else {
		os.unset_env(constants.ENV_HIDE_SENSITIVE)
		app_refresh_credits(a)
	}
	app_refresh_provider_status(a)
	app_mark_dirty(a)
}
