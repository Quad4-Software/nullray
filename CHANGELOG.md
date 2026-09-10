# Changelog

Notable changes for nullray.

## [Unreleased]

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
- Verify soft-skips make test when no Makefile exists instead of failing the gate.
- rag_reindex rebuilds memory and retained artifacts.
- RAG rejects zero vectors and surfaces forced-mode retrieve failures in the prompt.

### Fixed
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
