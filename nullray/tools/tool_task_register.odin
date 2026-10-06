// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Subagent tool registration for the tools registry.
*/

package tools

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
		description = "Spawn a subagent (explore/locate/architect/review/edit/orchestrate). locate returns CITES. architect returns a Done Contract. Returns summary or background id.",
		schema_json = `{"type":"object","properties":{"description":{"type":"string"},"prompt":{"type":"string"},"subagent_type":{"type":"string","description":"explore|locate|architect|review|edit|orchestrate"},"model":{"type":"string"},"provider":{"type":"string","description":"route to a different provider id (e.g. ollama, openrouter); default inherits the parent provider"},"isolation":{"type":"string"},"background":{"type":"string"},"group":{"type":"string"},"resume":{"type":"string"},"max_steps":{"type":"string"},"path_hints":{"type":"array","items":{"type":"string"}}},"required":["prompt"]}`,
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
		description = "Run adversarial verify on a finished spawn group (reviews worktree diffs) before apply",
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
		name = "models_list",
		description = "List active provider, default model, and approved-model policy (aliases, roles) for routing tasks",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_models_list,
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
		description = "List shared task board items; group filters to that group plus unscoped items. Shows blocked-by markers and done results",
		schema_json = `{"type":"object","properties":{"group":{"type":"string"}}}`,
		kind = .Read,
		run = tool_board_list,
	})
	registry_register(r, Tool{
		name = "board_add",
		description = "Add a task board item; blocked_on holds item ids that must be done before claim; group scopes the item",
		schema_json = `{"type":"object","properties":{"title":{"type":"string"},"blocked_on":{"type":"array","items":{"type":"string"},"description":"item ids that must be done first; comma list also accepted"},"group":{"type":"string"}},"required":["title"]}`,
		kind = .Read,
		run = tool_board_add,
	})
	registry_register(r, Tool{
		name = "board_claim",
		description = "Claim a task board item; refused while its blocked_on deps are not done",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`,
		kind = .Read,
		run = tool_board_claim,
	})
	registry_register(r, Tool{
		name = "board_done",
		description = "Mark a task board item done with a one-line result for the coordinator",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"result":{"type":"string","description":"one-line outcome for the coordinator"}},"required":["id"]}`,
		kind = .Read,
		run = tool_board_done,
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
