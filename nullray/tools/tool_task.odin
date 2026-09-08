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

	spec := subagent.Spawn_Spec{
		description = strings.clone(desc),
		prompt = strings.clone(len(prompt) > 0 ? prompt : desc),
		subagent_type = strings.clone(stype),
		model = strings.clone(model),
		background = bg,
		resume_id = strings.clone(resume),
		group_id = strings.clone(group),
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

unregister_subagent_tools :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	i := 0
	for i < len(r.tools) {
		if is_subagent_tool_name(r.tools[i].name) {
			ordered_remove(&r.tools, i)
			continue
		}
		i += 1
	}
}

register_subagent_tools :: proc(r: ^Registry, enabled: bool) {
	if r == nil {
		return
	}
	if !enabled {
		unregister_subagent_tools(r)
		return
	}
	registry_register(r, Tool{
		name = "task",
		description = "Spawn a subagent (explore/review/edit). Returns summary or background id.",
		schema_json = `{"type":"object","properties":{"description":{"type":"string"},"prompt":{"type":"string"},"subagent_type":{"type":"string"},"model":{"type":"string"},"isolation":{"type":"string"},"background":{"type":"string"},"group":{"type":"string"},"resume":{"type":"string"}},"required":["prompt"]}`,
		kind = .Read,
		run = tool_task,
	})
	registry_register(r, Tool{
		name = "agents_status",
		description = "List live agents and progress",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_agents_status,
	})
	registry_register(r, Tool{
		name = "agents_peek",
		description = "Peek one agent progress and result summary",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`,
		kind = .Read,
		run = tool_agents_peek,
	})
	registry_register(r, Tool{
		name = "agents_progress",
		description = "Publish a one-line progress note for this agent",
		schema_json = `{"type":"object","properties":{"note":{"type":"string"}},"required":["note"]}`,
		kind = .Read,
		run = tool_agents_progress,
	})
	registry_register(r, Tool{
		name = "agents_wait",
		description = "Wait/join a spawn group and return child summaries",
		schema_json = `{"type":"object","properties":{"group":{"type":"string"}},"required":["group"]}`,
		kind = .Read,
		run = tool_agents_wait,
	})
	registry_register(r, Tool{
		name = "agents_verify",
		description = "Run verify-all on a finished spawn group before apply",
		schema_json = `{"type":"object","properties":{"group":{"type":"string"},"second_opinion":{"type":"string"}},"required":["group"]}`,
		kind = .Read,
		run = tool_agents_verify,
	})
	registry_register(r, Tool{
		name = "knowledge_get",
		description = "Read a shared knowledge key",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}`,
		kind = .Read,
		run = tool_knowledge_get,
	})
	registry_register(r, Tool{
		name = "knowledge_put",
		description = "Write a shared knowledge key (authored)",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"},"value":{"type":"string"}},"required":["key","value"]}`,
		kind = .Read,
		run = tool_knowledge_put,
	})
	registry_register(r, Tool{
		name = "knowledge_list",
		description = "List knowledge keys (optional filter author:id or tag)",
		schema_json = `{"type":"object","properties":{"filter":{"type":"string"}}}`,
		kind = .Read,
		run = tool_knowledge_list,
	})
	registry_register(r, Tool{
		name = "model_use",
		description = "Switch session model to an approved model when unlocked",
		schema_json = `{"type":"object","properties":{"model":{"type":"string"}},"required":["model"]}`,
		kind = .Read,
		run = tool_model_use,
	})
	registry_register(r, Tool{
		name = "board_list",
		description = "List shared task board items",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_board_list,
	})
	registry_register(r, Tool{
		name = "board_add",
		description = "Add a task board item",
		schema_json = `{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}`,
		kind = .Read,
		run = tool_board_add,
	})
	registry_register(r, Tool{
		name = "board_claim",
		description = "Claim a task board item",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`,
		kind = .Read,
		run = tool_board_claim,
	})
	registry_register(r, Tool{
		name = "send_message",
		description = "Send a peer message (requires NULLRAY_SUBAGENT_TEAMS=1)",
		schema_json = `{"type":"object","properties":{"to":{"type":"string"},"body":{"type":"string"}},"required":["to","body"]}`,
		kind = .Read,
		run = tool_send_message,
	})
	registry_register(r, Tool{
		name = "read_messages",
		description = "Read peer messages for this agent",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_read_messages,
	})
}
