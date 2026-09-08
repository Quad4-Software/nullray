# Changelog

Notable changes for nullray.

Format follows Keep a Changelog and Semantic Versioning.

## [0.1.2] - 2026-09-08

### Added
- Large tool dumps go to .nullray/artifacts/ with a short status path and excerpt envelope. Peek with read_artifact or grep_artifact.
- The model sees a short projected history (recent turns and stubbed tool results). Clear and compact write back into the session transcript.
- Mid-turn clear and compact when context crosses the budget. Mode switches reset the provider window toward digests and stubs.
- Lean system prompt via NULLRAY_PROMPT=lean (auto under print). Mode-filtered tool list, shorter AGENTS head, skill bodies only through load_skill.
- Harness metrics on stderr (NULLRAY_HARNESS_METRICS=1 or NULLRAY_DEBUG=1) and in .usage.jsonl.
- Exact-then-fuzzy SEARCH/REPLACE for edit_file and apply_edits. Whitespace and CRLF drift no longer hard-fails. Same-file apply_edits hunks chain in memory.
- Tree-sitter repo map with a capped symbol digest in the system prompt and a repo_symbols peek tool.
- Failed NULLRAY_VERIFY runs list ranked path:line findings and may offload the full log to an artifact.

### Fixed
- Mid-turn clear and compact no longer fires on a fat system prompt alone. Budget uses non-system message size. Empty prepares are not counted as midturn events.
- Lean prompt lists tool names only. Schemas stay in the API tools array. AGENTS head is about 800 characters with a path pointer.
- With an explicit workspace (-w or NULLRAY_WORKSPACE), AGENTS.md is not loaded from the process cwd. That stopped host-repo instructions leaking into /tmp bench workspaces.
- OpenRouter HTTP 401 responses keep the provider message and point at ~/.config/nullray/env instead of a bare User not found.
- TLS RNG on hardened Linux: Mbed TLS shim adds a getrandom and /dev/urandom entropy source (fixes TLS RNG init failed).
- HTTP chunked bodies: bytes after response headers are decoded as chunks instead of appended raw (fixes leading chunk-size junk and truncated JSON).
- --print-strict no longer fails solely on max_steps when the turn had tool calls or workspace writes. Edit turns that hit the step budget still run one verify shot when verify is on.
- read_artifact defaults to a 200-line window (NULLRAY_ARTIFACT_READ_LINES) with a 32KB hard cap so peeks cannot re-bloat context.

### Changed
- LID stays on by default. NULLRAY_LID=0 turns off projection, artifact store, and phase reset. Envelopes remain without artifact=.
- Lean/print tools JSON uses a core allowlist, strips schema property descriptions, and omits all subagent tools when subagents are off. harness_tools_json is recorded in .usage.jsonl.
- Prepare write-back matches tool_call_id only (no name-only matching). Artifacts are GC'd on session destroy and --doctor (64MB quota, 7-day age).
- TUI collapses tool rows that carry artifact= to a one-line stub. Expand with /artifact ID in the side pane.
- Artifact threshold NULLRAY_ARTIFACT_CHARS (default 3000). Projection caps NULLRAY_PROJECTION_TURNS and NULLRAY_PROJECTION_TOOL_STUBS.
- Provider and fetch HTTP use sockets plus static Mbed TLS, nghttp2, and mlkem-native instead of libcurl. HTTPS prefers HTTP/2 when ALPN selects h2, else HTTP/1.1. Plain http stays HTTP/1.1. TLS 1.2 and 1.3 with X25519MLKEM768 hybrid PQ. System CAs via SSL_CERT_FILE / SSL_CERT_DIR. HTTP(S)_PROXY is not honored yet. No HTTP/3.

## [0.1.1] - 2026-09-07

### Added
- Nullray wordmark and square profile logo assets (nullray-word, nullray-profile).

### Fixed
- OpenCode Go and Zen chat requests send a stable x-opencode-session header so routing and cache affinity work.
- HTTP User-Agent uses nullray/VERSION instead of a stale nullray/0.6 string.

## [0.1.0] - 2026-09-07

### Added
- First release: Odin TUI coding agent with Landlock/seccomp sandbox, native tool loop, sessions, MCP, completions, and man page.
- Providers: OpenAI and OpenAI-compat hosts, Anthropic, Gemini, Groq, DeepSeek, Mistral, Together, Fireworks, xAI, Azure, OpenRouter, LM Studio, Ollama, OpenCode, Cerebras, Cohere, NVIDIA, DashScope.
- Modes ask, plan, review, edit. Headless --print. Done Contract plans with --plan-out / --plan-in. Optional post-edit verify.
- Subagents (task, roster, knowledge, leases, worktrees). Progressive skills. /setup wizard.
- Session usage (.usage.jsonl), /usage, --print --usage. Cost only when the provider sends it. --print-strict for CI-style exit checks.
- Hooks, project memory, local Git/Fossil VCS, shadow checkpoints with /undo and /checkpoint restore|diff.
- Ops profiles via NULLRAY_OPS (desktop, docker, kube, full). EXTRA_RO/RW env paths. Docker sock unix resolve. Intentional kube allow.
- Gated network VCS (push/pull/fetch, gh PR) behind NULLRAY_VCS_NETWORK. fetch_url with SSRF basics.
- Skills: linux-admin, docker-ops, kube-ops, git-workflow, hooks, docker-secure, unix-docs.
- Linux arm64/aarch64 release archives and install.sh selection. Landlock applies. Seccomp stays amd64-only.
- Packages: Docker/GHCR, Flatpak, slim AppImage, airgap SDK AppImage (make appimage-sdk), AUR nullray-bin recipe.
- Site pixel footer: Terminal Coding Agent.
- run_shell timeout_ms and NULLRAY_SHELL_TIMEOUT_MS (auto default 5m, cap 15m). Process-group kill on timeout.
- Identical tool-loop intervention then abort. Auto mode steps default to 80.
- Soft shell denies skipped under perms=yolo. --print-strict fails tool-only turns with no workspace writes.
- Shell output truncation marker at the byte cap.
- Elevate broker sleeps when idle. Broker not started when NULLRAY_ELEVATE=deny.
- Windows release builds via prebuilt Odin zip, vcpkg libcurl LIB path, and bin/nullray.exe out path.
