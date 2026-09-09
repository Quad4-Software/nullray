// SPDX-License-Identifier: 0BSD
/*
Task spawn and coordination tools for subagents.
*/

package tools

import "core:fmt"
import "core:strings"
import "nullray:subagent"

tool_task :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("subagent runtime not initialized", allocator)
	}
	desc, _ := json_arg_string_optional(args_json, "description", "", allocator)
	defer delete(desc)
	prompt, perr := json_arg_string_optional(args_json, "prompt", "", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(prompt)
	if len(prompt) == 0 && len(desc) == 0 {
		return "", strings.clone("task requires prompt or description", allocator)
	}
	stype, _ := json_arg_string_optional(args_json, "subagent_type", "explore", allocator)
	defer delete(stype)
	model, _ := json_arg_string_optional(args_json, "model", "", allocator)
	defer delete(model)
	isol_s, _ := json_arg_string_optional(args_json, "isolation", "", allocator)
	defer delete(isol_s)
	group, _ := json_arg_string_optional(args_json, "group", "", allocator)
	defer delete(group)
	resume, _ := json_arg_string_optional(args_json, "resume", "", allocator)
	defer delete(resume)
	bg, _ := json_arg_bool_string(args_json, "background", false)
	max_steps, _ := json_arg_int_optional(args_json, "max_steps", 0, allocator)
	path_hints, pherr := json_arg_strings_optional(args_json, "path_hints", allocator)
	if pherr != "" {
		return "", pherr
	}

	spec := subagent.Spawn_Spec{
		description = strings.clone(desc),
		prompt = strings.clone(len(prompt) > 0 ? prompt : desc),
		subagent_type = strings.clone(stype),
		model = strings.clone(model),
		background = bg,
		resume_id = strings.clone(resume),
		group_id = strings.clone(group),
		max_steps = max_steps,
		path_hints = path_hints,
	}
	if len(isol_s) > 0 {
		if isol, ok := subagent.isolation_from_string(isol_s); ok {
			spec.isolation = isol
			spec.isolation_set = true
		}
	}
	return subagent.spawn_child(rt, spec, allocator)
}

tool_agents_status :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	rt := subagent.runtime()
	if rt == nil {
		return strings.clone("(no runtime)", allocator), ""
	}
	return subagent.roster_status_text(&rt.roster, allocator), ""
}

tool_agents_peek :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, perr := json_arg_string(args_json, "id", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(id)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	return subagent.roster_peek_text(&rt.roster, id, allocator), ""
}

tool_agents_progress :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	note, perr := json_arg_string(args_json, "note", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(note)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	aid := subagent.runtime_current_agent(rt, context.temp_allocator)
	subagent.roster_set_progress(&rt.roster, aid, note)
	subagent.lease_heartbeat(&rt.leases, aid)
	return strings.clone("ok", allocator), ""
}

tool_agents_wait :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	group, gerr := json_arg_string(args_json, "group", allocator)
	if gerr != "" {
		return "", gerr
	}
	defer delete(group)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	if !subagent.roster_group_all_done(&rt.roster, group) {
		return "", strings.clone("group still running", allocator)
	}
	return subagent.roster_group_results_text(&rt.roster, group, allocator), ""
}

tool_agents_verify :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	group, gerr := json_arg_string(args_json, "group", allocator)
	if gerr != "" {
		return "", gerr
	}
	defer delete(group)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	report, verr := subagent.verify_all(rt, group, rt.provider, allocator)
	if verr != "" {
		subagent.destroy_verify_report(&report)
		return "", verr
	}
	text := subagent.verify_report_text(report, allocator)
	second, _ := json_arg_bool_string(args_json, "second_opinion", false)
	if second {
		op, oerr := subagent.verify_second_opinion(rt, group, rt.provider, report, context.temp_allocator)
		if oerr == "" && len(op) > 0 {
			combined := fmt.aprintf("%s\n\nSECOND_OPINION:\n%s", text, op, allocator = allocator)
			delete(text)
			text = combined
		}
	}
	subagent.destroy_verify_report(&report)
	return text, ""
}

tool_knowledge_get :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	key, perr := json_arg_string(args_json, "key", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(key)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	return subagent.knowledge_get(&rt.knowledge, key, allocator)
}

tool_knowledge_put :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	key, perr := json_arg_string(args_json, "key", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(key)
	value, verr := json_arg_string(args_json, "value", allocator)
	if verr != "" {
		return "", verr
	}
	defer delete(value)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	aid := subagent.runtime_current_agent(rt, context.temp_allocator)
	if kerr := subagent.knowledge_put(&rt.knowledge, key, value, aid, {}, allocator); kerr != "" {
		return "", kerr
	}
	subagent.roster_add_knowledge_key(&rt.roster, aid, key)
	return strings.clone("ok", allocator), ""
}

tool_knowledge_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	filter, _ := json_arg_string_optional(args_json, "filter", "", allocator)
	defer delete(filter)
	rt := subagent.runtime()
	if rt == nil {
		return strings.clone("(no runtime)", allocator), ""
	}
	return subagent.knowledge_list(&rt.knowledge, filter, allocator), ""
}

tool_model_use :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	model, perr := json_arg_string(args_json, "model", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(model)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	if subagent.policy_is_locked() || rt.model_locked {
		return "", strings.clone("model locked by user", allocator)
	}
	resolved, rerr := subagent.policy_resolve("main", model, rt.provider != nil ? rt.provider.default_model : "", "", allocator)
	if rerr != "" {
		return "", rerr
	}
	if rt.provider != nil {
		delete(rt.provider.default_model)
		rt.provider.default_model = strings.clone(resolved)
	}
	delete(rt.main_model)
	rt.main_model = strings.clone(resolved)
	out := fmt.aprintf("model set to %s", resolved, allocator = allocator)
	delete(resolved)
	return out, ""
}

tool_board_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	rt := subagent.runtime()
	if rt == nil {
		return strings.clone("(no runtime)", allocator), ""
	}
	return subagent.board_list_text(&rt.board, allocator), ""
}

tool_board_add :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	title, perr := json_arg_string(args_json, "title", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(title)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	id, berr := subagent.board_add(&rt.board, title, allocator)
	if berr != "" {
		return "", berr
	}
	return id, ""
}

tool_board_claim :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, perr := json_arg_string(args_json, "id", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(id)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	aid := subagent.runtime_current_agent(rt, context.temp_allocator)
	if cerr := subagent.board_claim(&rt.board, id, aid, allocator); cerr != "" {
		return "", cerr
	}
	return strings.clone("ok", allocator), ""
}

tool_send_message :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	to, terr := json_arg_string(args_json, "to", allocator)
	if terr != "" {
		return "", terr
	}
	defer delete(to)
	body, berr := json_arg_string(args_json, "body", allocator)
	if berr != "" {
		return "", berr
	}
	defer delete(body)
	rt := subagent.runtime()
	if rt == nil {
		return "", strings.clone("no runtime", allocator)
	}
	aid := subagent.runtime_current_agent(rt, context.temp_allocator)
	if serr := subagent.peer_send(&rt.messages, aid, to, body, allocator); serr != "" {
		return "", serr
	}
	return strings.clone("ok", allocator), ""
}

tool_read_messages :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	rt := subagent.runtime()
	if rt == nil {
		return strings.clone("(no runtime)", allocator), ""
	}
	aid := subagent.runtime_current_agent(rt, context.temp_allocator)
	return subagent.peer_read(&rt.messages, aid, allocator), ""
}
