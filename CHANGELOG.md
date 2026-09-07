# Changelog

Notable changes for nullray.

Format follows Keep a Changelog and Semantic Versioning.

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
- Packages: Docker/GHCR, Flatpak, slim AppImage, airgap SDK AppImage (make appimage-sdk), AUR nullray-bin recipe.
