// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
session/update notification emitters. Assistant text and reasoning stream
as chunks, tool calls open in_progress and close with a flat update.
*/

package acp

import "core:strings"
import "nullray:mcp"

@(private)
emit_update :: proc(srv: ^Server, session_id: string, update_json: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionId":`)
	mcp.write_json_string(&b, session_id)
	strings.write_string(&b, `,"update":`)
	strings.write_string(&b, update_json)
	strings.write_byte(&b, '}')
	notify_session(srv, session_id, "session/update", strings.to_string(b))
}

@(private)
emit_text_update :: proc(srv: ^Server, session_id: string, kind: string, text: string) {
	if len(text) == 0 {
		return
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionUpdate":`)
	mcp.write_json_string(&b, kind)
	strings.write_string(&b, `,"content":{"type":"text","text":`)
	mcp.write_json_string(&b, text)
	strings.write_string(&b, `}}`)
	emit_update(srv, session_id, strings.to_string(b))
}

emit_message_chunk :: proc(srv: ^Server, session_id: string, text: string) {
	emit_text_update(srv, session_id, "agent_message_chunk", text)
}

emit_thought_chunk :: proc(srv: ^Server, session_id: string, text: string) {
	emit_text_update(srv, session_id, "agent_thought_chunk", text)
}

emit_tool_start :: proc(srv: ^Server, session_id: string, call_id, title, name: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionUpdate":"tool_call","toolCallId":`)
	mcp.write_json_string(&b, call_id)
	strings.write_string(&b, `,"title":`)
	mcp.write_json_string(&b, title)
	strings.write_string(&b, `,"name":`)
	mcp.write_json_string(&b, name)
	strings.write_string(&b, `,"kind":`)
	mcp.write_json_string(&b, acp_tool_kind(name))
	strings.write_string(&b, `,"status":"in_progress"}`)
	emit_update(srv, session_id, strings.to_string(b))
}

emit_tool_done :: proc(srv: ^Server, session_id: string, call_id: string, failed: bool, raw_output: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionUpdate":"tool_call_update","toolCallId":`)
	mcp.write_json_string(&b, call_id)
	strings.write_string(&b, `,"status":`)
	mcp.write_json_string(&b, failed ? "failed" : "completed")
	if len(raw_output) > 0 {
		strings.write_string(&b, `,"rawOutput":`)
		mcp.write_json_string(&b, raw_output)
	}
	strings.write_byte(&b, '}')
	emit_update(srv, session_id, strings.to_string(b))
}

emit_mode_update :: proc(srv: ^Server, session_id: string, mode_id: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionUpdate":"current_mode_update","currentModeId":`)
	mcp.write_json_string(&b, mode_id)
	strings.write_byte(&b, '}')
	emit_update(srv, session_id, strings.to_string(b))
}

// Map nullray tool names onto the ACP ToolKind enum.
acp_tool_kind :: proc(name: string) -> string {
	switch name {
	case "read_file", "list_dir", "glob_files", "repo_map", "read_artifact",
	     "vcs_status", "vcs_diff", "vcs_log", "memory_get", "memory_list",
	     "list_skills", "list_scaffolds", "read_man", "read_tldr", "read_info",
	     "read_help", "lang_doc":
		return "read"
	case "grep_files", "grep_artifact", "search_tools", "memory_search",
	     "rag_query", "apropos":
		return "search"
	case "write_file", "edit_file", "apply_edits", "memory_put",
	     "memory_delete", "memory_forget", "scaffold", "vcs_commit":
		return "edit"
	case "run_shell", "run_script":
		return "execute"
	case "fetch_url":
		return "fetch"
	case:
		return "other"
	}
}

// Tool errors reach the event stream as text, not flags. Prefix match the
// common failure shapes so tool_call_update can report failed.
acp_tool_failed :: proc(output: string) -> bool {
	t := strings.to_lower(strings.trim_space(output), context.temp_allocator)
	for p in ([]string{"error", "failed", "denied", "blocked", "timeout", "cancelled", "permission denied"}) {
		if strings.has_prefix(t, p) {
			return true
		}
	}
	return false
}
