// SPDX-License-Identifier: 0BSD
/*
Shared provider activate path for /provider and keyboard cycle.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"

/*
Apply the registry active provider to session, subagents, and NULLRAY_PROVIDER.
Caller must set or cycle the registry first.
*/
app_activate_provider :: proc(a: ^App) {
	p := provider.registry_active(&a.registry)
	if p == nil {
		session.session_set_status(&a.session, "no provider")
		return
	}

	session.session_remember_model(&a.session, p.id, p.default_model)
	subagent.runtime_set_provider(&a.subagents, p)

	kvs := []config.Env_KV{{key = constants.ENV_PROVIDER, val = p.id}}
	if err := config.merge_env_keys(kvs[:]); len(err) > 0 {
		session.session_set_status(&a.session, err)
		delete(err)
		app_mark_dirty(a)
		return
	}

	app_refresh_credits(a)
	app_refresh_provider_status(a)

	ready := provider.provider_is_ready(p)
	msg := fmt.tprintf("provider %s · %s", p.name, p.default_model)
	if !ready {
		msg = fmt.tprintf("%s · %s · /setup", msg, provider.provider_readiness_label(p))
	} else if !a.hide_sensitive && len(a.credits_label) > 0 {
		msg = fmt.tprintf("%s · %s", msg, a.credits_label)
	}
	session.session_set_status(&a.session, msg)
	app_mark_dirty(a)
}

slash_cmd_provider :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		p := provider.registry_active(&a.registry)
		if p == nil {
			session.session_set_status(&a.session, "no provider")
			return
		}
		ready := provider.provider_readiness_label(p)
		session.session_set_status(
			&a.session,
			fmt.tprintf("provider %s (%s) · %s · %s", p.id, p.name, p.default_model, ready),
		)
		return
	}

	low := strings.to_lower(rest, context.temp_allocator)
	switch low {
	case "setup":
		app_setup_open(a, false)
		return
	case "next":
		provider.registry_cycle(&a.registry, 1)
		app_activate_provider(a)
		return
	case "prev", "previous":
		provider.registry_cycle(&a.registry, -1)
		app_activate_provider(a)
		return
	}

	if !provider.registry_set_active(&a.registry, rest) {
		session.session_set_status(&a.session, "usage: /provider [ID|next|prev|setup] · /providers")
		return
	}
	app_activate_provider(a)
}

slash_cmd_providers :: proc(a: ^App, args: string) {
	_ = args
	active := provider.registry_active(&a.registry)
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "providers:\n")
	for &p in a.registry.providers {
		mark := " "
		if active != nil && p.id == active.id {
			mark = "*"
		}
		ready := provider.provider_readiness_label(&p)
		fmt.sbprintf(&b, "%s %-16s %-18s %s\n", mark, p.id, p.name, ready)
	}
	strings.write_string(&b, "use /provider ID · /setup for keys")
	out := strings.to_string(b)
	session.session_push_assistant(&a.session, out)
	delete(out)
	session.session_set_status(&a.session, "providers")
	app_mark_dirty(a)
}
