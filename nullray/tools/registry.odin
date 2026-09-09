// SPDX-License-Identifier: 0BSD
/*
Tool registry: registration, lookup, and init of built-ins.
*/

package tools

Tool_Kind :: enum {
	Read,
	Write,
	Shell,
	Mcp,
}

Tool_Proc :: #type proc(args_json: string, allocator := context.allocator) -> (result: string, err: string)

External_Run_Proc :: #type proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string)

Tool :: struct {
	name:        string,
	description: string,
	schema_json: string,
	kind:        Tool_Kind,
	gate:        int,
	run:         Tool_Proc,
}

Registry :: struct {
	tools:          [dynamic]Tool,
	external_run:   External_Run_Proc,
	external_user:  rawptr,
}

g_registry: Registry

registry :: proc() -> ^Registry {
	return &g_registry
}

registry_init :: proc(r: ^Registry) {
	r^ = {}
	r.tools = make([dynamic]Tool)
	registry_register(r, Tool{
		name = "read_file",
		description = "Read a UTF-8 text file under the workspace (optional offset/limit line slices)",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"string","description":"1-based start line"},"limit":{"type":"string","description":"max lines to return"}},"required":["path"]}`,
		kind = .Read,
		run = tool_read_file,
	})
	registry_register(r, Tool{
		name = "write_file",
		description = "Write UTF-8 text to a file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"},"allow_godfile":{"type":"string","description":"true to allow growth past the structure limit"}},"required":["path","content"]}`,
		kind = .Write,
		run = tool_write_file,
	})
	registry_register(r, Tool{
		name = "list_dir",
		description = "List entries in a directory under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`,
		kind = .Read,
		run = tool_list_dir,
	})
	registry_register(r, Tool{
		name = "repo_map",
		description = "Shallow relative tree of a workspace directory (depth and byte budget capped)",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"depth":{"type":"string","description":"0-3, default 2"},"focus":{"type":"string","description":"optional filename glob or substring"}},"required":[]}`,
		kind = .Read,
		run = tool_repo_map,
	})
	registry_register(r, Tool{
		name = "edit_file",
		description = "Replace a unique old_string with new_string in a UTF-8 workspace file. Prefer small unique anchors. Exact match first, then whitespace-tolerant fuzzy (ambiguous matches are refused)",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string","description":"true or false"},"allow_godfile":{"type":"string","description":"true to allow growth past the structure limit"}},"required":["path","old_string","new_string"]}`,
		kind = .Write,
		run = tool_edit_file,
	})
	registry_register(r, Tool{
		name = "grep_files",
		description = "Search files under the workspace (substring or regex). Uses ripgrep when available. Optional case_insensitive, regex, engine=auto|rg|builtin",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"case_insensitive":{"type":"string","description":"true or false"},"regex":{"type":"string","description":"true or false"},"engine":{"type":"string","description":"auto, rg, or builtin"}},"required":["pattern"]}`,
		kind = .Read,
		run = tool_grep_files,
	})
	registry_register(r, Tool{
		name = "glob_files",
		description = "List files matching a glob pattern under the workspace",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"}},"required":["pattern"]}`,
		kind = .Read,
		run = tool_glob_files,
	})
	registry_register(r, Tool{
		name = "run_shell",
		description = "Run a shell command in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"command":{"type":"string"},"timeout_ms":{"type":"string","description":"optional timeout in milliseconds"}},"required":["command"]}`,
		kind = .Shell,
		run = tool_run_shell,
	})
	registry_register(r, Tool{
		name = "apply_edits",
		description = "Apply multiple search-replace edits or create files under the workspace. Each old_string must uniquely identify its target. Exact then fuzzy whitespace match, ambiguous refused",
		schema_json = `{"type":"object","properties":{"allow_godfile":{"type":"string","description":"true to allow growth past the structure limit"},"edits":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string"}},"required":["path","old_string","new_string"]}},"files":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}}`,
		kind = .Write,
		run = tool_apply_edits,
	})
	registry_register(r, Tool{
		name = "run_script",
		description = "Write and run a short script (sh/bash/python) in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"language":{"type":"string"},"code":{"type":"string"},"timeout_ms":{"type":"string"}},"required":["language","code"]}`,
		kind = .Shell,
		run = tool_run_script,
	})
	registry_register(r, Tool{
		name = "list_skills",
		description = "List available skill ids and descriptions",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_list_skills,
	})
	registry_register(r, Tool{
		name = "load_skill",
		description = "Load a skill body into context by id from list_skills",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`,
		kind = .Read,
		run = tool_load_skill,
	})
	registry_register(r, Tool{
		name = "memory_get",
		description = "Read a project memory value by key",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}`,
		kind = .Read,
		run = tool_memory_get,
	})
	registry_register(r, Tool{
		name = "memory_put",
		description = "Store a durable project memory value",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"},"value":{"type":"string"}},"required":["key","value"]}`,
		kind = .Write,
		run = tool_memory_put,
	})
	registry_register(r, Tool{
		name = "memory_list",
		description = "List project memory keys with preview and updated timestamp",
		schema_json = `{"type":"object","properties":{"filter":{"type":"string"}}}`,
		kind = .Read,
		run = tool_memory_list,
	})
	registry_register(r, Tool{
		name = "memory_delete",
		description = "Delete a project memory entry by key",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}`,
		kind = .Write,
		run = tool_memory_delete,
	})
	registry_register(r, Tool{
		name = "memory_forget",
		description = "Forget a project memory entry by key (alias of memory_delete)",
		schema_json = `{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}`,
		kind = .Write,
		run = tool_memory_forget,
	})
	registry_register(r, Tool{
		name = "memory_search",
		description = "Search project memory by substring with simple ranking",
		schema_json = `{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"string","description":"max hits (default 20)"}},"required":["query"]}`,
		kind = .Read,
		run = tool_memory_search,
	})
	registry_register(r, Tool{
		name = "compact_context",
		description = "Request context compaction when a task phase ends (explore to edit). Clears stale tool results.",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_compact_context,
	})
	registry_register(r, Tool{
		name = "read_artifact",
		description = "Read a large tool payload previously offloaded to an artifact id (optional offset/limit lines)",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"offset":{"type":"string","description":"1-based start line"},"limit":{"type":"string","description":"max lines to return"}},"required":["id"]}`,
		kind = .Read,
		run = tool_read_artifact,
	})
	registry_register(r, Tool{
		name = "grep_artifact",
		description = "Search a substring inside an offloaded artifact by id",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"pattern":{"type":"string"}},"required":["id","pattern"]}`,
		kind = .Read,
		run = tool_grep_artifact,
	})
	registry_register(r, Tool{
		name = "read_man",
		description = "Read a Linux man page as plain text (page name, optional section 1-8)",
		schema_json = `{"type":"object","properties":{"page":{"type":"string"},"section":{"type":"string"},"max_chars":{"type":"string"}},"required":["page"]}`,
		kind = .Read,
		run = tool_read_man,
	})
	registry_register(r, Tool{
		name = "apropos",
		description = "Search man page names and descriptions (man -k)",
		schema_json = `{"type":"object","properties":{"keyword":{"type":"string"}},"required":["keyword"]}`,
		kind = .Read,
		run = tool_apropos,
	})
	registry_register(r, Tool{
		name = "read_tldr",
		description = "Read a local tldr page when tldr/tealdeer is installed",
		schema_json = `{"type":"object","properties":{"page":{"type":"string"},"platform":{"type":"string"},"max_chars":{"type":"string"}},"required":["page"]}`,
		kind = .Read,
		run = tool_read_tldr,
	})
	registry_register(r, Tool{
		name = "read_info",
		description = "Read a GNU info node as plain text",
		schema_json = `{"type":"object","properties":{"node":{"type":"string"},"max_chars":{"type":"string"}},"required":["node"]}`,
		kind = .Read,
		run = tool_read_info,
	})
	registry_register(r, Tool{
		name = "read_help",
		description = "Run command --help for a PATH binary (no shell)",
		schema_json = `{"type":"object","properties":{"command":{"type":"string"},"max_chars":{"type":"string"}},"required":["command"]}`,
		kind = .Read,
		run = tool_read_help,
	})
	registry_register(r, Tool{
		name = "lang_doc",
		description = "Read installed language docs (go doc, pydoc, ri, rustup doc)",
		schema_json = `{"type":"object","properties":{"lang":{"type":"string","description":"go, python, ruby, or rust"},"query":{"type":"string"},"max_chars":{"type":"string"}},"required":["lang","query"]}`,
		kind = .Read,
		run = tool_lang_doc,
	})
	registry_register(r, Tool{
		name = "scaffold",
		description = "Copy a named secure scaffold template into the workspace",
		schema_json = `{"type":"object","properties":{"name":{"type":"string"},"dest":{"type":"string"},"force":{"type":"string"}},"required":["name"]}`,
		kind = .Write,
		run = tool_scaffold,
	})
	registry_register(r, Tool{
		name = "audit_structure",
		description = "Audit workspace files against .nullray/policy.json line thresholds",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_structure,
	})
	registry_register(r, Tool{
		name = "audit_actions",
		description = "Audit GitHub Actions workflow security",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_actions,
	})
	registry_register(r, Tool{
		name = "audit_dockerfile",
		description = "Audit Dockerfile image pins, users, and shell pipes",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_dockerfile,
	})
	registry_register(r, Tool{
		name = "audit_compose",
		description = "Audit Compose privileged mode and Docker socket mounts",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_compose,
	})
	registry_register(r, Tool{
		name = "audit_owasp",
		description = "Audit source for secrets, injection, XSS sinks, and path traversal patterns",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_owasp,
	})
	registry_register(r, Tool{
		name = "audit_deps",
		description = "Audit dependency manifests for lock files",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_audit_deps,
	})
	registry_register(r, Tool{
		name = "vcs_status",
		description = "Show local Git or Fossil repository status",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_vcs_status,
	})
	registry_register(r, Tool{
		name = "vcs_diff",
		description = "Show local Git or Fossil changes",
		schema_json = `{"type":"object","properties":{"revision":{"type":"string"}}}`,
		kind = .Read,
		run = tool_vcs_diff,
	})
	registry_register(r, Tool{
		name = "vcs_log",
		description = "Show local Git or Fossil history",
		schema_json = `{"type":"object","properties":{"count":{"type":"integer"}}}`,
		kind = .Read,
		run = tool_vcs_log,
	})
	registry_register(r, Tool{
		name = "vcs_commit",
		description = "Commit local Git or Fossil changes without pushing",
		schema_json = `{"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}`,
		kind = .Write,
		run = tool_vcs_commit,
	})
	registry_register(r, Tool{
		name = "vcs_branch",
		description = "Show or create and switch a local Git or Fossil branch",
		schema_json = `{"type":"object","properties":{"name":{"type":"string"}}}`,
		kind = .Write,
		run = tool_vcs_branch,
	})
	registry_register(r, Tool{
		name = "vcs_merge",
		description = "Merge a local branch, refusing dirty trees by default",
		schema_json = `{"type":"object","properties":{"target":{"type":"string"},"allow_dirty":{"type":"string","description":"true or false"}},"required":["target"]}`,
		kind = .Write,
		run = tool_vcs_merge,
	})
	registry_register(r, Tool{
		name = "vcs_rebase",
		description = "Rebase Git only, refusing dirty trees by default",
		schema_json = `{"type":"object","properties":{"target":{"type":"string"},"allow_dirty":{"type":"string","description":"true or false"}},"required":["target"]}`,
		kind = .Write,
		run = tool_vcs_rebase,
	})
	registry_register(r, Tool{
		name = "vcs_push",
		description = "Push to remote (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{"remote":{"type":"string"},"ref":{"type":"string"},"force":{"type":"string","description":"true or false"}}}`,
		kind = .Write,
		run = tool_vcs_push,
	})
	registry_register(r, Tool{
		name = "vcs_pull",
		description = "Pull from remote (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{"remote":{"type":"string"},"ref":{"type":"string"}}}`,
		kind = .Write,
		run = tool_vcs_pull,
	})
	registry_register(r, Tool{
		name = "vcs_fetch",
		description = "Fetch from remote (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{"remote":{"type":"string"}}}`,
		kind = .Write,
		run = tool_vcs_fetch,
	})
	registry_register(r, Tool{
		name = "vcs_pr_create",
		description = "Create a GitHub PR via gh (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}},"required":["title"]}`,
		kind = .Write,
		run = tool_vcs_pr_create,
	})
	registry_register(r, Tool{
		name = "vcs_pr_view",
		description = "View the current GitHub PR via gh (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_vcs_pr_view,
	})
	registry_register(r, Tool{
		name = "fetch_url",
		description = "Fetch a public http(s) URL as text (HTML to plain when useful, size-capped, no browser)",
		schema_json = `{"type":"object","properties":{"url":{"type":"string"},"format":{"type":"string","description":"auto, text, or raw"},"max_chars":{"type":"string"}},"required":["url"]}`,
		kind = .Read,
		run = tool_fetch_url,
	})
}

registry_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	snapshots_destroy()
	delete(r.tools)
	r^ = {}
}

tools_init :: proc() {
	registry_init(&g_registry)
}

tools_destroy :: proc() {
	registry_destroy(&g_registry)
}

registry_set_external_run :: proc(r: ^Registry, p: External_Run_Proc, user: rawptr = nil) {
	if r == nil {
		return
	}
	r.external_run = p
	r.external_user = user
}

registry_register :: proc(r: ^Registry, t: Tool) {
	if r == nil {
		return
	}
	for existing, i in r.tools {
		if existing.name == t.name {
			r.tools[i] = t
			return
		}
	}
	append(&r.tools, t)
}

registry_find :: proc(r: ^Registry, name: string) -> (^Tool, bool) {
	if r == nil {
		return nil, false
	}
	for &t in r.tools {
		if t.name == name {
			return &t, true
		}
	}
	return nil, false
}

registry_list :: proc(r: ^Registry) -> []Tool {
	if r == nil {
		return {}
	}
	return r.tools[:]
}

set_external_run :: proc(p: External_Run_Proc, user: rawptr = nil) {
	registry_set_external_run(&g_registry, p, user)
}

register :: proc(t: Tool) {
	registry_register(&g_registry, t)
}

find :: proc(name: string) -> (^Tool, bool) {
	return registry_find(&g_registry, name)
}

list :: proc() -> []Tool {
	return registry_list(&g_registry)
}
