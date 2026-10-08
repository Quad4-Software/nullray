// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Built-in tool registration for the default registry.
*/

package tools

registry_register_builtins :: proc(r: ^Registry) {
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
		description = "Shallow relative tree of a workspace directory with symbol names on source files (depth and byte budget capped)",
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
		description = "Run a shell command in the workspace when sandbox permits. background=true returns a pollable task_id and writes .nullray/tasks/<id>.log. Pass task_id to poll.",
		schema_json = `{"type":"object","properties":{"command":{"type":"string"},"timeout_ms":{"type":"string","description":"optional timeout in milliseconds"},"background":{"type":"string","description":"true to run in the background"},"task_id":{"type":"string","description":"poll a background task"}},"required":[]}`,
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
		description = "Store a durable project memory value. Scoped recall keys surface at the moment a tool runs: recall.path.<glob> matches file paths (** crosses directories), recall.cmd.<substr> matches shell commands, recall.tool.<name> matches a tool call",
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
		description = "Search project memory (hybrid lexical and semantic when RAG is on)",
		schema_json = `{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"string","description":"max hits (default 20)"}},"required":["query"]}`,
		kind = .Read,
		run = tool_memory_search,
	})
	registry_register(r, Tool{
		name = "rag_status",
		description = "Show RAG index status (chunks, embed model, stale flag)",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_rag_status,
	})
	registry_register(r, Tool{
		name = "rag_reindex",
		description = "Rebuild the RAG index. scope=memory (default) covers project memory and retained artifacts; scope=code indexes the live tree when NULLRAY_RAG_CODE=1; scope=all does both",
		schema_json = `{"type":"object","properties":{"scope":{"type":"string","description":"memory|code|all"}}}`,
		kind = .Write,
		run = tool_rag_reindex,
	})
	registry_register(r, Tool{
		name = "rag_query",
		description = "Semantic RAG query over indexed memory, artifacts, and code. scope=code limits hits to the live tree lane when indexed",
		schema_json = `{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"string"},"scope":{"type":"string","description":"all|memory|code"}},"required":["query"]}`,
		kind = .Read,
		run = tool_rag_query,
	})
	registry_register(r, Tool{
		name = "search_tools",
		description = "Search tool names and descriptions, return schemas, and activate matches for lean prompts",
		schema_json = `{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}`,
		kind = .Read,
		run = tool_search_tools,
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
		name = "list_scaffolds",
		description = "List available scaffold templates and packs",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_list_scaffolds,
	})
	registry_register(r, Tool{
		name = "scaffold",
		description = "Copy a named secure scaffold template or pack into the workspace",
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
		schema_json = `{"type":"object","properties":{"revision":{"type":"string"},"scope":{"type":"string","description":"working|staged|unstaged|base"},"base":{"type":"string","description":"base revision when scope=base"},"paths":{"type":"string","description":"comma-separated path filters"}}}`,
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
		name = "vcs_pr_checks",
		description = "List GitHub PR check runs via gh (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_vcs_pr_checks,
	})
	registry_register(r, Tool{
		name = "vcs_pr_watch",
		description = "Wait inside the tool until PR checks reach a terminal state or new review/issue comments appear. Returns a status= report. Use after opening or pushing to a PR instead of shell sleep loops (needs NULLRAY_VCS_NETWORK=1)",
		schema_json = `{"type":"object","properties":{"pr":{"type":"string","description":"PR number, URL, or branch; default current branch"},"wait_for":{"type":"string","description":"any, checks, or comments"},"timeout_sec":{"type":"string","description":"max seconds to wait, up to 1800"},"interval_sec":{"type":"string","description":"poll interval, 10-120"}}}`,
		kind = .Read,
		run = tool_vcs_pr_watch,
	})
	register_ask_tools(r)
	register_tui_tools(r)
	register_harness_tools(r)
	registry_register(r, Tool{
		name = "fetch_url",
		description = "Preferred way to read a public http(s) page. Returns status, final url, title, and plain text (HTML stripped, links kept as text (url)). Soft-redirects (meta refresh / location.replace) are followed. Prefer this over curl/wget in run_shell. via=flaresolverr for protected pages. For RSS/Atom feeds use fetch_rss.",
		schema_json = `{"type":"object","properties":{"url":{"type":"string","description":"absolute http(s) URL"},"format":{"type":"string","description":"auto (default, HTML to text), text, or raw"},"max_chars":{"type":"string","description":"cap returned text, default large"},"via":{"type":"string","description":"optional fetch provider id, e.g. flaresolverr"}},"required":["url"]}`,
		kind = .Read,
		run = tool_fetch_url,
	})
	registry_register(r, Tool{
		name = "fetch_rss",
		description = "Fetch and summarize an RSS 2.0 or Atom feed. Returns feed title and a list of items (title, link, date, snippet). Use count to cap items. Then fetch_url an item link for full text. Prefer this over curl for feeds.",
		schema_json = `{"type":"object","properties":{"url":{"type":"string","description":"absolute feed URL (rss/atom/xml)"},"count":{"type":"string","description":"max items, default 10, cap 30"}},"required":["url"]}`,
		kind = .Read,
		run = tool_fetch_rss,
	})
	registry_register(r, Tool{
		name = "web_search",
		description = "Search the web for titles, URLs, and snippets when you do not already know the URL. Needs NULLRAY_SEARCH_URL (SearXNG) or a vendor key. For a known docs URL, call fetch_url instead. For feeds, call fetch_rss.",
		schema_json = `{"type":"object","properties":{"query":{"type":"string"},"queries":{"type":"array","items":{"type":"string"},"description":"combined multi-query fan-out, deduped"},"backends":{"type":"array","items":{"type":"string"},"description":"provider ids to federate across; default auto"},"count":{"type":"string","description":"max results, default 5, cap 10"},"scope":{"type":"string","description":"general, code, or news"},"context_max_chars":{"type":"string","description":"cap the result envelope, default 4000"}},"required":[]}`,
		kind = .Read,
		run = tool_web_search,
	})
}
