# Changelog

Notable changes for nullray.

## [Unreleased]

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
