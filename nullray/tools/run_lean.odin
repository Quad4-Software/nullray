// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tool dispatch, mode gating, and OpenAI tools JSON.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:subagent"

subagent_runtime_enabled :: proc() -> bool {
	rt := subagent.runtime()
	if rt == nil {
		return false
	}
	return subagent.runtime_enabled(rt)
}

SUBAGENT_TOOL_NAMES :: []string{
	"task",
	"agents_status",
	"agents_peek",
	"agents_progress",
	"agents_wait",
	"agents_verify",
	"knowledge_get",
	"knowledge_put",
	"knowledge_list",
	"models_list",
	"model_use",
	"board_list",
	"board_add",
	"board_claim",
	"board_done",
	"send_message",
	"read_messages",
}

is_subagent_tool_name :: proc(name: string) -> bool {
	for n in SUBAGENT_TOOL_NAMES {
		if n == name {
			return true
		}
	}
	return false
}

lean_core_tool :: proc(name: string) -> bool {
	switch name {
	case "read_file", "write_file", "edit_file", "apply_edits", "list_dir", "repo_map",
		"grep_files", "glob_files", "run_shell", "run_script",
		"load_skill", "list_skills", "compact_context", "search_tools",
		"read_artifact", "grep_artifact",
		"memory_get", "memory_put", "memory_list", "memory_delete", "memory_forget", "memory_search",
		"rag_status", "rag_query", "rag_reindex",
		"read_man", "apropos", "read_tldr", "read_info", "read_help", "lang_doc", "fetch_url", "fetch_rss", "web_search",
		"list_scaffolds", "scaffold", "audit_structure",
		"vcs_status", "vcs_diff", "vcs_log", "vcs_commit", "vcs_branch", "vcs_merge",
		"vcs_rebase", "vcs_push", "vcs_pull", "vcs_fetch",
		"vcs_pr_create", "vcs_pr_view", "vcs_pr_checks", "vcs_pr_watch",
		"todo_write", "todo_update", "todo_add", "todo_list",
		"schedule_prompt", "schedule_list", "schedule_cancel", "watch_checkpoint",
		"harness_list", "harness_run":
		return true
	}
	return false
}

/*
Audit scanners for lean when NULLRAY_HUNT is on. Keeps review hunt from
instructing audit_* while tools_json omits them.
*/
lean_hunt_tool :: proc(name: string) -> bool {
	switch name {
	case "audit_owasp", "audit_deps", "audit_dockerfile", "audit_compose", "audit_actions":
		return true
	}
	return false
}

lean_hunt_tools_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HUNT, context.temp_allocator); ok {
		raw := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		switch raw {
		case "", "0", "false", "no", "off", "disable", "disabled":
			return false
		}
		return true
	}
	return false
}

/*
Lean print keeps a small coordination subset when subagents are enabled.
Board/messaging stay out to protect tools-JSON size.
*/
lean_subagent_tool :: proc(name: string) -> bool {
	switch name {
	case "task", "agents_status", "agents_peek", "agents_progress",
		"agents_wait", "agents_verify",
		"knowledge_get", "knowledge_put", "knowledge_list", "models_list",
		"todo_list":
		return true
	}
	return false
}

