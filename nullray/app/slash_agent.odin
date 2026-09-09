// SPDX-License-Identifier: 0BSD
/*
Slash commands: agent mode, models, subagents, tools.
*/

package app

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:subagent"
import "nullray:tools"

slash_cmd_mode :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("mode %s (ask|plan|review|edit)", agent.mode_string(a.session.agent_mode)))
		return
	}
	m, ok := agent.mode_from_string(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /mode ask|plan|review|edit")
		return
	}
	session.session_set_mode(&a.session, m)
}

slash_cmd_hunt :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		p := agent.hunt_from_env()
		samp := agent.sampling_from_env(p)
		label := agent.sampling_label(samp, context.temp_allocator)
		session.session_set_status(
			&a.session,
			fmt.tprintf("hunt %s %s (off|auto|balanced|explore|oracle|adversarial)", agent.hunt_profile_string(p), label),
		)
		return
	}
	p, ok := agent.hunt_profile_from_string(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /hunt off|auto|balanced|explore|oracle|adversarial")
		return
	}
	if p == .Off {
		os.unset_env(constants.ENV_HUNT)
		os.unset_env(constants.ENV_HUNT_PHASE)
	} else {
		os.set_env(constants.ENV_HUNT, agent.hunt_profile_string(p))
		if p == .Auto {
			agent.hunt_set_phase(.Explore)
		}
		if a.session.agent_mode != .Review {
			session.session_set_mode(&a.session, .Review)
		}
	}
	session.session_rebuild_system_prompt(&a.session)
	samp := agent.sampling_from_env(p)
	label := agent.sampling_label(samp, context.temp_allocator)
	session.session_set_status(&a.session, fmt.tprintf("hunt %s %s", agent.hunt_profile_string(p), label))
}

slash_cmd_temp :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		if v, ok := os.lookup_env(constants.ENV_TEMPERATURE, context.temp_allocator); ok {
			session.session_set_status(&a.session, fmt.tprintf("temp %s", v))
		} else {
			session.session_set_status(&a.session, "temp default (usage: /temp 0-2|off)")
		}
		return
	}
	low := strings.to_lower(rest, context.temp_allocator)
	if low == "off" || low == "default" {
		os.unset_env(constants.ENV_TEMPERATURE)
		session.session_set_status(&a.session, "temp default")
		return
	}
	n, n_ok := strconv.parse_f64(rest)
	if !n_ok || n < 0 || n > 2 {
		session.session_set_status(&a.session, "usage: /temp 0-2|off")
		return
	}
	os.set_env(constants.ENV_TEMPERATURE, fmt.tprintf("%g", n))
	session.session_set_status(&a.session, fmt.tprintf("temp %g", n))
}

slash_cmd_top_p :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		if v, ok := os.lookup_env(constants.ENV_TOP_P, context.temp_allocator); ok {
			session.session_set_status(&a.session, fmt.tprintf("top_p %s", v))
		} else {
			session.session_set_status(&a.session, "top_p default (usage: /top_p 0-1|off)")
		}
		return
	}
	low := strings.to_lower(rest, context.temp_allocator)
	if low == "off" || low == "default" {
		os.unset_env(constants.ENV_TOP_P)
		session.session_set_status(&a.session, "top_p default")
		return
	}
	n, n_ok := strconv.parse_f64(rest)
	if !n_ok || n <= 0 || n > 1 {
		session.session_set_status(&a.session, "usage: /top_p 0-1|off")
		return
	}
	os.set_env(constants.ENV_TOP_P, fmt.tprintf("%g", n))
	session.session_set_status(&a.session, fmt.tprintf("top_p %g", n))
}

slash_cmd_model :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	p := provider.registry_active(&a.registry)
	if len(rest) == 0 {
		lock := subagent.policy_is_locked() || a.subagents.model_locked
		model := p != nil ? p.default_model : a.session.model
		session.session_set_status(&a.session, fmt.tprintf("model %s lock=%s", model, lock ? "on" : "off"))
		return
	}
	low := strings.to_lower(rest, context.temp_allocator)
	if low == "lock" {
		subagent.policy_set_lock(true)
		a.subagents.model_locked = true
		if p != nil {
			delete(a.subagents.main_model)
			a.subagents.main_model = strings.clone(p.default_model)
		}
		session.session_set_status(&a.session, "model locked")
		return
	}
	if low == "unlock" {
		subagent.policy_set_lock(false)
		a.subagents.model_locked = false
		session.session_set_status(&a.session, "model unlocked")
		return
	}
	if subagent.policy_is_locked() || a.subagents.model_locked {
		session.session_set_status(&a.session, "model locked (use /model unlock)")
		return
	}
	resolved, err := subagent.policy_resolve("main", rest, p != nil ? p.default_model : "", "", context.temp_allocator)
	if err != "" {
		session.session_set_status(&a.session, err)
		return
	}
	if p != nil {
		delete(p.default_model)
		p.default_model = strings.clone(resolved)
		session.session_remember_model(&a.session, p.id, p.default_model)
	}
	delete(a.subagents.main_model)
	a.subagents.main_model = strings.clone(resolved)
	subagent.runtime_set_provider(&a.subagents, p)
	session.session_set_status(&a.session, fmt.tprintf("model %s", resolved))
}

slash_cmd_models :: proc(a: ^App, args: string) {
	_ = args
	text := subagent.policy_list_text(context.temp_allocator)
	session.session_set_status(&a.session, text)
}

slash_cmd_agents :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	parts := strings.fields(rest, context.temp_allocator)
	if len(parts) == 0 || parts[0] == "list" {
		text := subagent.roster_status_text(&a.subagents.roster, context.temp_allocator)
		enabled := subagent.runtime_enabled(&a.subagents)
		session.session_set_status(&a.session, fmt.tprintf("subagents %s\n%s", enabled ? "on" : "off", text))
		return
	}
	switch parts[0] {
	case "off":
		subagent.runtime_set_session_off(&a.subagents, true)
		tools.register_subagent_tools(&a.tools_reg, false)
		session.session_set_status(&a.session, "subagents off")
	case "on":
		subagent.runtime_set_session_off(&a.subagents, false)
		tools.register_subagent_tools(&a.tools_reg, subagent.runtime_enabled(&a.subagents))
		session.session_set_status(&a.session, "subagents on")
	case "knowledge":
		text := subagent.knowledge_list(&a.subagents.knowledge, "", context.temp_allocator)
		session.session_set_status(&a.session, text)
	case "cancel":
		if len(parts) < 2 {
			session.session_set_status(&a.session, "usage: /agents cancel ID")
			return
		}
		subagent.roster_request_cancel(&a.subagents.roster, parts[1])
		session.session_set_status(&a.session, fmt.tprintf("cancel requested for %s", parts[1]))
	case "apply":
		force := false
		group := ""
		for i in 1 ..< len(parts) {
			if parts[i] == "--force" {
				force = true
			} else {
				group = parts[i]
			}
		}
		if len(group) == 0 {
			session.session_set_status(&a.session, "usage: /agents apply GROUP [--force]")
			return
		}
		ok, reason := subagent.roster_apply_allowed(&a.subagents.roster, group, force)
		if !ok {
			session.session_set_status(&a.session, reason)
			return
		}
		ws := ""
		if st := sandbox.state(); st != nil {
			ws = st.workspace
		}
		merged, merr := subagent.roster_apply_worktrees(&a.subagents.roster, group, ws, context.temp_allocator)
		if merr != "" {
			session.session_set_status(&a.session, merr)
			return
		}
		session.session_set_status(&a.session, fmt.tprintf("apply ok (merged %d) force=%v", merged, force))
	case:
		session.session_set_status(&a.session, "usage: /agents [list|on|off|knowledge|cancel ID|apply GROUP [--force]]")
	}
}

slash_cmd_approve :: proc(a: ^App, args: string) {
	_ = args
	path := a.session.last_plan_path
	if len(path) == 0 {
		session.session_set_status(&a.session, "no plan artifact to approve")
		return
	}
	if err := session.session_approve_plan_file(&a.session, path); len(err) > 0 {
		session.session_set_status(&a.session, err)
		return
	}
}

slash_cmd_tools :: proc(a: ^App, args: string) {
	_ = args
	a.session.tools_enabled = !a.session.tools_enabled
	mode := "tools on"
	if !a.session.tools_enabled {
		mode = "tools off"
	}
	session.session_set_status(&a.session, mode)
}

slash_cmd_reasoning :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("reasoning %s (none|minimal|low|medium|high|xhigh|max)", a.session.reasoning_effort))
		return
	}
	effort, ok := session.normalize_reasoning_effort(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /reasoning none|minimal|low|medium|high|xhigh|max")
		return
	}
	delete(a.session.reasoning_effort)
	a.session.reasoning_effort = strings.clone(effort)
	session.session_set_status(&a.session, fmt.tprintf("reasoning %s", a.session.reasoning_effort))
}

slash_cmd_improve :: proc(a: ^App, args: string) {
	_ = args
	app_improve_prompt(a)
}
