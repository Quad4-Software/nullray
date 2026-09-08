# Changelog

Notable changes for nullray.

Format follows Keep a Changelog and Semantic Versioning.

## [0.1.2] - 2026-09-08

### Added
- Big tool output is saved under .nullray/artifacts/. The model sees a short summary. Peek with read_artifact or grep_artifact.
- Shorter chat history for the model (recent turns, stubbed old tool output).
- Lean prompts in print mode (NULLRAY_PROMPT=lean, or auto under --print).
- Harness stats on stderr and in .usage.jsonl when NULLRAY_HARNESS_METRICS=1 or NULLRAY_DEBUG=1.
- Softer file edits: exact match first, then fuzzy whitespace. Multi-hunk apply_edits on one file chains in memory.
- Optional repo symbol digest in the prompt, plus repo_symbols.
- Failed verify runs show path:line hints and may save the full log as an artifact.

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
- Ops profiles (NULLRAY_OPS), optional network VCS, packaging (Docker, Flatpak, AppImage, AUR).
- Linux arm64 builds. Shell timeouts and anti-loop limits. Elevate broker when needed.
