# Changelog

Notable changes for nullray.

Format follows Keep a Changelog and Semantic Versioning.

## [Unreleased]

### Added
- Locate subagent (`task` `subagent_type=locate`): budgeted read-only search that returns a CITES `path:start-end` block to the parent. Env: NULLRAY_LOCATE_STEPS (default 4), NULLRAY_LOCATE_PARALLEL (default 8), NULLRAY_LOCATE_MAX_CITES (default 12). Tools: repo_map, glob_files, grep_files, read_file, list_dir. task accepts max_steps and path_hints.
- `repo_map` tool: shallow workspace tree with depth and byte budget.
- Session rename moves transcript/meta/usage files. `/rename` alias, `--rename-session N --as NEW [--force]`. `/new` without a name picks a unique `session-<unix>` id. Collisions refuse unless `--force`.
- Session transcripts default to MessagePack (`.msgpack`) with JSONL load fallback. Atomic `.tmp` then rename. `--export-session` always writes JSONL.
- `/drop N`, `--inspect-session [--follow]`, trim backups under `sessions/backups/`, stdin-as-context for print when args and piped stdin both exist (`NULLRAY_STDIN_CONTEXT_MAX`).
- Writing quirks (`NULLRAY_QUIRKS`, `/quirks`): `tool_xml_in_reasoning`, `tool_json_in_content`, `reasoning_only_stall`.
- Local probe gate `NULLRAY_LOCAL_PROBE=0`, auto-select live local when no provider is set, Landlock port 8080, `lm-studio` alias, `LLAMA_CPP_HOST` in setup.
- Project memory v2: `memory_delete`/`memory_forget`, compact, `memory_search`, typed key prefixes, MEMORY.md index + topics/, richer list.
- OpenRouter ZDR extension: `NULLRAY_OPENROUTER_ZDR=off|warn|require` (default warn).
- llamacpp provider for llama-server (default http://127.0.0.1:8080/v1). Host LLAMA_CPP_HOST, optional LLAMA_CPP_API_KEY. Aliases llama.cpp, llama-cpp, llama.
- Setup provider step groups Local (ollama, lmstudio, llamacpp) above Cloud.
- NULLRAY_PROVIDER_FALLBACKS for cross-provider chat failover on dead key or payment errors (tries real chat, not only /models).
- OPENROUTER_CREDITS_KEY optional separate credits key. Clearer OpenRouter credits vs chat auth errors.
- HTTP(S)_PROXY / ALL_PROXY / NO_PROXY dial with CONNECT for HTTPS. Kept through privacy scrub.
- Windows Job Object sandbox (KILL_ON_JOB_CLOSE) instead of a stub.
- Print JSON findings schema (findings.count / items / trailer_found) plus cost_note when provider omits cost.
- Vuln hunt profiles: NULLRAY_HUNT / --hunt / /hunt. auto runs explore then oracle in print. Role-routed subagent temps when hunt is on (explore high, verify/review low).
- NULLRAY_TEMPERATURE, NULLRAY_TOP_P, NULLRAY_HUNT_PHASE, /temp, /top_p.
- Stronger UNTRUSTED_DATA framing for tools and MCP. MCP blocked on untrusted remote workspaces unless NULLRAY_WORKSPACE_TRUST=1 or NULLRAY_MCP_ALLOW_ANY=1.
- Tool capability gate: `--gate` / `NULLRAY_GATE` / `/gate` 0..3 (ask/allow/yolo aliases).
- Shell always-deny for systemd-run, busctl, gdbus, docker.sock, privileged containers, force-push, and SQL DROP/TRUNCATE.
- `NULLRAY_SHELL_NET` and `NULLRAY_FETCH_ALLOW`. curl/wget/nc confirm even under yolo. fetch SSRF covers IPv6 and AAAA.
- Workspace hooks trust handoff (`/hooks trust`, `NULLRAY_HOOKS_TRUST`). Doctor escape checklist.
- Optional `NULLRAY_MCP_CONFIRM=1`. MCP tool descriptions prefixed with `UNTRUSTED_MCP_TOOL`.
- TUI UTF-8 stdin and rune-boundary caret. Multiline input (up to 8 rows). Remappable stop= bind. NULLRAY_VIEW_AUTO and `/view auto`. Click-expand for artifacts and truncated code. `/status` overlay. Mode chip in the banner.

### Changed
- `grep_files` match lines are `path:lineno:text` (1-based line numbers).

### Fixed
- Lean prompts list only lean-core tool names (match tools_json), not the full mode catalog.
- Session lock acquire discards both return values from session_try_lock (build break).
- redact_secrets deletes prior buffers with the caller allocator (fixes free invalid pointer on tool offload).
- Hunt auto oracle phase resets/caps explore transcript before the second billed pass. Lean hunt preamble is shorter. Lean hunt includes audit_* tools. Findings JSON prefers the oracle section only.
- Print ephemeral no longer skips explicit memory_put/delete/forget (workspace `.nullray/memory` stays durable).
- Locate CITES destroy matches the allocator used by format_locate_summary (fixes SIGSEGV after locate).
- LID envelope field sanitize, secret-aware excerpts, opening delimiter neutralization, artifact peeks re-redact, write_file size cap, child summary redact.
- Untrusted AGENTS.md wrap until workspace trust. Clipboard `/copy` runs through `redact_secrets`.
- HTTP Host header no longer doubles the port (broke Ollama and other non-default ports).
- Ollama/LM Studio send Origin: http://127.0.0.1 so CORS allows local OpenAI-compat chat.
- Local providers skip reasoning_effort / thinking fields Ollama rejects.
- Print mode respects NULLRAY_AGENT_TOOLS=0 (was forced on).
- Provider failover keeps plain local model names; only swaps vendor/model ids to the fallback default.
- chat-smoke skips cleanly when OpenRouter rejects the key.
- OpenRouter User not found messages point at key/account and fallbacks.
- Block tools from reading `~/.config/nullray/env` and session/crash stores. Symlink and quote-split `.env` shell bypasses closed.
- Tool→model redaction covers `sk-` / bearer / proxy userinfo, not only home paths.
- `fetch_url` re-checks SSRF on redirects and blocks decimal/hex/CGNAT/DNS-resolved private hosts.
- Failover uses pre-scrub API key cache so vendor keys are not replaced by `NULLRAY_API_KEY` after privacy scrub.
- Worktree subagents bind tools to the child workspace (thread-local override).
- Deny `$OPENROUTER_API_KEY`-style env expansion and spaced `curl | bash` in shell policy.
- Config `env` and askpass secret files create with mode 0600. `https://` proxy URLs rejected until TLS-to-proxy exists.
- UNTRUSTED_DATA framing always wraps tool/MCP bodies and neutralizes end delimiters.
- TUI: mid-rune caret, silent paste reject, busy Enter with no feedback, Esc wiping slash suggestions, selection auto-copy, force-follow on idle when scrolled up, improve worker racing the input builder.

### Changed
- Speculative allowlisted reads are on by default. Set NULLRAY_SPECULATE=0 to disable.
- audit_owasp covers secrets, injection sinks, XSS, path traversal, unsafe deserializers.
- Review mode auto-suggests on hunt, vuln, CVE, and related keywords.

## [0.2.0] - 2026-09-08

### Added
- Big tool output is saved under .nullray/artifacts/. The model sees a short summary. Peek with read_artifact or grep_artifact.
- Shorter chat history for the model (recent turns, stubbed old tool output).
- Lean prompts in print mode (NULLRAY_PROMPT=lean, or auto under --print).
- Harness stats on stderr and in .usage.jsonl when NULLRAY_HARNESS_METRICS=1 or NULLRAY_DEBUG=1.
- Softer file edits: exact match first, then fuzzy whitespace. Multi-hunk apply_edits on one file chains in memory.
- Optional repo symbol digest in the prompt, plus repo_symbols.
- Failed verify runs show path:line hints and may save the full log as an artifact.
- Optional speculative read tools (NULLRAY_SPECULATE=1): seal streamed tool calls without trusting partial JSON, run allowlisted reads early, reuse on hash match. Cap with NULLRAY_SPECULATE_PARALLEL (default 2).

### Fixed
- Context cleanup no longer triggers just because the system prompt is large.
- Explicit -w / NULLRAY_WORKSPACE no longer pulls AGENTS.md from the process cwd.
- OpenRouter 401 errors point at ~/.config/nullray/env.
- HTTPS works on hardened Linux (TLS RNG). Chunked HTTP responses no longer corrupt JSON.
- --print-strict ignores a step-limit stop when the turn already did useful work.
- read_artifact defaults to 200 lines and caps at 32KB.

### Changed
- Context harness is on by default. NULLRAY_LID=0 turns it off.
- Lean/print sends a smaller tools list (still includes read_man and apropos, plus a few subagent tools when subagents are on).
- Tool rows with an artifact id collapse in the TUI. Expand with /artifact ID.
- Old artifacts are cleaned on session end and --doctor.
- Network stack is sockets + Mbed TLS + HTTP/2 (no libcurl). HTTP(S)_PROXY still ignored.

## [0.1.1] - 2026-09-07

### Added
- Wordmark and profile logo assets.

### Fixed
- OpenCode Go and Zen send a stable x-opencode-session header.
- User-Agent uses nullray/VERSION.

## [0.1.0] - 2026-09-07

### Added
- First release: TUI coding agent with sandbox, tools, sessions, MCP, and man pages.
- Many chat providers (OpenAI-compat, Anthropic, Gemini, OpenRouter, Ollama, and others).
- Modes ask, plan, review, edit. Headless --print. Plans with --plan-out / --plan-in. Optional verify.
- Subagents, skills, /setup wizard, session usage, hooks, memory, local VCS, /undo checkpoints.
- Ops profiles (NULLRAY_OPS), optional network VCS, packaging (Docker, Flatpak, AppImage).
