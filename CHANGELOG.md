# Changelog

Notable changes for nullray.

Format follows Keep a Changelog and Semantic Versioning.

## [0.1.1] - 2026-09-07

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
