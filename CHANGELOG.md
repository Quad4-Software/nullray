# Changelog

Notable changes for nullray.

## [Unreleased]

## [0.6.1] - 2026-10-05

### Fixed
- Release packaging pins refreshed for the rotated upstream appimagetool build so AppImage artifacts verify and build again.

## [0.6.0] - 2026-10-05

### Added
- Long tool results and thinking blocks fold to a marker plus their tail lines in the TUI. Click a block to expand or collapse it, /expand toggles all at once, and NULLRAY_COLLAPSE=0 disables folding.
- Documentation site at nullray.xyz/docs covering install, providers, configuration, modes, the TUI, commands, CLI flags, sessions, sandbox, security, skills, MCP, subagents, memory, and troubleshooting.
- nullray now adopts credentials and defaults from other AI CLIs already configured on the machine. API keys, custom endpoints, and the chosen provider/model are read from Claude Code, OpenCode, pi, Codex, Gemini CLI, Qwen Code, Crush, goose, aider, aichat, and llm config files, so a first run works without the setup wizard when a key is found. Only unset variables are filled, helper commands are never executed, and adopted values never appear in logs. --doctor lists what was detected, and NULLRAY_ADOPT=0 disables adoption.
- ANTHROPIC_BASE_URL now points the anthropic provider at a Messages-compatible endpoint or proxy.
- llama.cpp auto-detection also tries port 9931, the new llama-server default, and adopts whichever port answers.
- NULLRAY_HTTP_TIMEOUT overrides the 120s chat timeout for slow local inference.
- NULLRAY_SANDBOX_PORTS allows extra TCP ports when sandbox net is local, and ports from configured provider host URLs are allowed automatically.
- NULLRAY_JSON_MODE=1 and NULLRAY_JSON_SCHEMA=<schema> emit response_format json_object/json_schema on OpenAI-compatible providers, and llama.cpp enforces the shape with a grammar, for deterministic structured output.
- NULLRAY_PROMPT=tiny ships a minimal prompt and core tool set for small local models, and auto resolves to it whenever the active provider is local.
- NULLRAY_JUDGE optionally scores run completion through a decision backend: jev (System One compatible APIs like OpenCode Zen), laya (a local laya-serve instance), or chat (the active provider). NULLRAY_JUDGE_KEY sets the key and NULLRAY_JUDGE_CONFIDENCE the pass threshold; a failing score reports judge_fail and trips --print-strict. NULLRAY_JUDGE_RETRY=1 escalates a judged failure through NULLRAY_PROVIDER_FALLBACKS until the judge passes.

### Fixed
- LLAMA_CPP_API_KEY and LM_API_TOKEN reached providers only before the privacy scrub, so keyed llama.cpp and LM Studio servers always failed with 401.
- LLAMA_CPP_HOST, LM_STUDIO_HOST, OPENAI_BASE_URL, OPENAI_ORG_ID, ANTHROPIC_BASE_URL, and AZURE_OPENAI_ENDPOINT were scrubbed from the environment, so custom server addresses were ignored.
- Streaming chat dropped error bodies, hiding server messages like Invalid API Key behind bare HTTP codes.
- Errors from local providers now name the fix: which key to set on a 401, and --ctx-size or num_ctx when the prompt is too large.
- Tool calls from weaker models that use name variants (read-file, run shell, default_api.read_file) now resolve to the right tool, and genuinely unknown names get a did-you-mean hint instead of a dead end.
- Bare JSON tool-call objects emitted as text ({"name": ..., "arguments": ...}) are now dispatched like native tool calls.
- Malformed tool-call arguments no longer poison llama.cpp sessions; invalid argument payloads are sanitized before they go back into request history.

## [0.5.1] - 2026-09-29

### Fixed
- AppImage tool pin refreshed for the rotated upstream type2 runtime so the release jobs can fetch it again.

## [0.5.0] - 2026-09-29

### Added
- Session tabs like opencode: a strip under the title bar shows every open session. /new and /resume open new tabs, /tab list|new|open name|next|prev|close|N manages them, ctrl-x is a prefix (n new, w close, arrows switch), f4 and shift-tab cycle, and tabs are clickable including a + button. The strip scrolls with ‹ › overflow markers to keep the active tab visible (cap 16). Background tabs keep running and flag when done. The busy indicator now shows elapsed seconds and the live tool. Tab layout persists across restarts via open_tabs.
- Image, audio, and video attachments. In the TUI, /attach on a media file queues it for the next message; /attach lists the queue and /attach clear empties it. Print mode adds repeatable --image, --audio, --video, and --media flags. Older turns keep a text marker and stop resending the payload after NULLRAY_MEDIA_TURNS (default 2). NULLRAY_MEDIA=0 disables, NULLRAY_MEDIA_MAX caps file size (default 15MB).
- /models now lists the live catalog of the active provider, marks the current model, and tags OpenCode Zen entries that need the messages, responses, gemini, or systemone surface. Entries gain context-window and price details when the models.dev catalog cache is warm. /models policy keeps the old approved-model view.
- Per-model surface routing now follows the models.dev catalog (cached under the config dir, 24h refresh), which also fixes opencode-go: qwen3.x stays on chat except qwen3.8-flash, and minimax-m3/m2.7 use messages. NULLRAY_MODELSDEV=0 disables the cache.
- OpenCode Zen claude and qwen models work through the Anthropic Messages surface, streamed and non-streamed, with tool calls and thinking budgets.
- The anthropic provider now talks to the real Messages endpoint instead of a chat/completions path that never existed.
- NULLRAY_PROVIDER accepts zen as an alias for opencode.
- Desktop notifications when a background tab finishes or a print run ends. NULLRAY_NOTIFY=auto|desktop|osc|bell|off picks the backend: a native helper (notify-send, osascript, or a PowerShell toast), the OSC 9 terminal escape (tmux-aware), or a plain bell.
- Scoped memory recall. Keys like recall.path.<glob>, recall.cmd.<substr>, and recall.tool.<name> inject the matching lesson into the tool result at the moment it matters. NULLRAY_RECALL=0 disables.
- Opt-in semantic index over the live tree. NULLRAY_RAG_CODE=1 enables it, rag_reindex scope=code indexes, and rag_query scope=code restricts hits. Files are capped and secret-screened, and stale files are flagged in results.
- Cache usage reporting. Provider-reported cache hits land in usage.jsonl and /usage as cache_read so prefix-cache health is visible.

### Fixed
- Esc in one tab no longer aborts other tabs. HTTP streams and shell commands are owned by the session that started them, so cancel now hits only that session; its subagent children still stop with it.
- Elevated commands actually went through the privilege broker only when its response arrived within a few microseconds of the request file landing. The wait now lasts up to 30s, so askpass elevation works as designed instead of silently falling back to in-process exec.
- Orphan elevate brokers no longer pile up after an unclean exit; the broker exits when its parent disappears.
- OpenRouter /credits label is now lock-protected; the background fetch could race the draw path.
- RAG no longer tries to embed through OpenCode Zen, which has no embeddings endpoint.
- OpenCode models on unsupported surfaces (gpt, grok, muse, gemini, jev) fail fast with a pointer to compatible picks instead of a cryptic protocol error.
- MCP stdio servers that batch several JSON-RPC frames in one write no longer lose messages after the first newline, which used to stall tool calls until timeout.
- A hook whose command never reads stdin can no longer wedge the agent turn past the hook timeout. Hook stdin is fed from a helper thread.
- File edits, writes, multi-edits, and undo/checkpoint restores now write atomically (temp file plus rename) and keep the original permission bits, so a crash mid-edit cannot truncate a workspace file.
- A synchronous subagent turn no longer erases the parent worker's cancel binding or session bind, so Esc still stops the rest of the parent turn after an in-thread child returns.
- PreToolUse hooks no longer stall for the full timeout on commands that read stdin. The hook input JSON was also malformed by an unescaped brace in the format string, so hooks received corrupt payloads. Both fixed, and hooks now correctly block tools, including run_shell write attempts.
- A chat worker abandoned on teardown timeout can no longer write into a freed Session. The session is kept alive instead.
- Mid-turn context write-back (compaction and cleared tool results) no longer mutates the session message list from the worker thread. It is now marshalled to the UI thread, ordered before the turn commit, so drawing a busy tab cannot race history rewrites.
- Verify-on runs with no detectable test command no longer pass silently. The turn nudges once for a reproduction test or a concrete check before the agent can claim done.
- Denying a pending shell command now also drops any unconsumed one-shot allow token, and the Compact keybind refuses to run while a turn is in flight.
- Hook trust state, deferred search_tools names, shell approval state, and sandbox state now live on the heap allocator and are mutex-guarded where workers share them.

## [0.4.0] - 2026-09-14

### Added
- Local review bot via --review and /review local. Reviews Git or Fossil diffs with working, staged, unstaged, and base scopes. No forge required. Use --include-untracked for new files.
- Review findings accept critical, major, minor, trivial, and info severities for bot-style reports.
- Plan mode shows a short Done Contract example and nudges incomplete plans to rewrite required sections.
- list_scaffolds tool and lean print visibility for scaffolds and structure audit.
- Multi-file scaffold packs (nullray-workspace, odin-cli) plus a greenfield skill.
- Step-anchored plan apply after approve, with a steps sidecar next to the plan file.
- Architect subagent type that returns a Done Contract for the parent.
- Local-first embeddings and project RAG under .nullray/rag with hybrid memory_search and retrieved memory in the system prompt.
- search_tools finds deferred tool schemas and activates them for lean prompts.
- Verify failures write traces and skill drafts under .nullray/traces for human review.
- Plan step rewind notes under .nullray/plan-rewind (file undo stays on /undo).
- Compaction writes .nullray/HANDOFF.md for the next context window.
- Terminal-Bench adapter and scorecard under scripts/terminal-bench.

### Changed
- /status shows plan step progress and the steps sidecar path.
- Auto mode turns on post-edit verify when unset. Verify picks go test, cargo test, npm test, or pytest when there is no Makefile.
- Sandbox grants language toolchain caches under home by default and keeps Go module caches out of the workspace.
- rag_reindex rebuilds memory and retained artifacts.
- RAG rejects zero vectors and surfaces forced-mode retrieve failures in the prompt.

### Fixed
- Crash during tool-heavy chat turns when freeing streamed tool call lists.
- Print --timeout exits soon after the deadline instead of hanging on a stuck chat worker.
- Man and docs tool children time out and cancel cleanly instead of hanging past --timeout.
- Turns that finish tools with no assistant text get one finalize nudge for a real answer.
- --fail-on-findings exits on blocking severity lines, not a FINDINGS trailer count alone.
- OpenRouter --list-models no longer fails on large model catalogs.
- Print-mode --message-file and plan or out paths outside the private tmp root work under soft sandbox.
- Verify Makefile detection and RAG/traces/handoff paths honor NULLRAY_WORKSPACE and thread workspace overrides.
- Large LID artifact embeds no longer stall the turn (8KB index cap).
- RAG query no longer double-allocates embed error strings.
- Shell verify no longer treats missing exit_code as success.
- Print-strict fails when verify was enabled after writes but never ran.

## [0.3.1] - 2026-09-09

### Added
- Offline docs tools: tldr, GNU info, command --help, and lang_doc for go/python/ruby/rust.
- grep_files supports case-insensitive and regex search, and uses ripgrep when available.
- Soft sandbox grants read-only host docs caches by default (tldr, rustup, cargo bin). NULLRAY_DOCS=0 turns that off.

### Changed
- fetch_url works in ask and plan modes and turns HTML into readable text.
- go lang_doc writes its cache under the sandbox temp dir so stdlib docs work without opening home.

### Fixed
- Docs sandbox grants no longer follow symlink caches or treat HOME as a docs root.
- Docs tool children no longer inherit API keys and similar secret env vars.
- lang_doc rejects path traversal in queries.
- Large AGENTS.md no longer crashes print mode when lean prompt truncates it.
- Esc and Ctrl-C stop a busy turn without tearing down the session under the worker.
- Quit waits for the agent to finish stopping before exit.

## [0.3.0] - 2026-09-09

### Added
- Locate subagent: finds file spans and hands path:start-end cites back to the parent.
- repo_map tool for a quick workspace tree.
- Rename sessions from the TUI or CLI. Bare /new picks a unique name.
- Faster session files (MessagePack). Export still writes JSONL.
- /drop to trim history. Inspect sessions. Backups under sessions/backups/.
- Pipe stdin into print mode when you also pass a prompt.
- Quirks mode for models that bury tool calls in reasoning or content.
- llama.cpp / llama-server provider, plus auto-pick a live local model.
- Stronger project memory: search, delete, forget, prefixes, MEMORY.md topics.
- OpenRouter zero-data-retention modes (warn by default, optional require).
- Fail over to another provider when the key is dead or unpaid.
- HTTP(S) proxy support (CONNECT for HTTPS).
- Windows process sandbox via Job Objects.
- Vuln hunt mode (--hunt / /hunt). auto runs explore then a second pass.
- Temperature and top_p controls.
- Tool permission gate 0..3 (ask / allow / yolo).
- Safer shell defaults and fetch allowlists. MCP confirm option.
- TUI: UTF-8 paste, multiline input, view auto-open, artifact expand, /status.

### Changed
- Speculative read-ahead is on by default (NULLRAY_SPECULATE=0 to turn off).
- Review mode suggests itself when you talk about vulns or CVEs.
- grep_files lines include line numbers.

### Fixed
- Ephemeral print sessions still keep memory put/delete/forget.
- Locate no longer crashes after returning cites.
- Print usage rolls subagent tokens from locate/task children into the session total.
- Hunt auto spends less on the second pass and keeps audit tools in lean mode.
- Local Ollama / LM Studio chat works again (Host and Origin headers).
- Print mode respects turning tools off.
- Clearer OpenRouter auth and credits errors.
- Secrets stay out of tool output, clipboard copy, and config files (mode 0600).
- fetch_url blocks private hosts on redirects too.
- Worktree subagents edit the child tree, not the parent by mistake.
- TUI caret, paste, busy Enter, and scroll-follow polish.

## [0.2.0] - 2026-09-08

### Added
- Large tool dumps go to artifacts. Peek with read_artifact / grep_artifact.
- Leaner prompts and shorter chat history in print mode.
- Fuzzy file edits and multi-hunk apply on one file.
- Optional speculative reads while the model streams tool calls.
- Path:line hints when verify fails.

### Fixed
- HTTPS on hardened Linux. Chunked HTTP no longer corrupts JSON.
- Workspace flag no longer loads AGENTS.md from the wrong directory.
- OpenRouter 401s point at your config env file.
- Artifact peeks default to 200 lines (32KB cap).

### Changed
- Context harness on by default (NULLRAY_LID=0 to disable).
- Artifact tool rows collapse in the TUI. Expand with /artifact ID.
- Built-in TLS and HTTP/2 (no libcurl).

## [0.1.1] - 2026-09-07

### Fixed
- OpenCode Go and Zen session routing.
- Stable User-Agent string.

## [0.1.0] - 2026-09-07

### Added
- First release: TUI coding agent with sandbox, tools, sessions, MCP, and man pages.
- Many chat providers (OpenAI-compat, Anthropic, Gemini, OpenRouter, Ollama, and others).
- Modes ask, plan, review, edit. Headless --print. Plans and optional verify.
- Subagents, skills, /setup, usage, hooks, memory, local VCS, /undo.
- Ops profiles, packaging (Docker, Flatpak, AppImage).
