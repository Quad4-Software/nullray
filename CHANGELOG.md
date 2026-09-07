# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-07 [Unreleased]

### Added

- Subagents: `task` tool, roster, shared knowledge, path leases, git worktrees, verify-all gate, `/agents`, `/model`.
- Model policy via `models.json` (approved list, aliases, roles) and `NULLRAY_MODEL_LOCK` / `/model lock`.
- Caps: `NULLRAY_SUBAGENTS` (default 3), `NULLRAY_SUBAGENT_DEPTH`, `--no-subagents`.
- Progressive skills: YAML frontmatter catalog in the system prefix, `load_skill` / `list_skills`, auto-activate into the transcript (cache-safe).
- `/skills` (alias `/skill`) lists loaded skills or shows one by id.
- Skill CLI: `--list-skills`, `--install-skill`, `--uninstall-skill`, plus `--skills` / `NULLRAY_SKILLS` extra roots.
- Context pipeline: tool-result clearing, wired `NULLRAY_COMPACT_CHARS` auto-compact, slim tool catalog text, lean AGENTS.md cap, `read_file` offset/limit.
- Done Contract plans (`## Verify` / `## Success` / `## Budget` / `## Failure`), `/approve`, edit-mode plan summary injection.
- Post-edit verify stop gate (`NULLRAY_VERIFY`, `/verify`) with truncated output and circuit breaker.

### Fixed

- Plan artifact writes under Landlock no longer call `make_directory_all` from `/` (which denied parent opens like `/tmp`). Parents are created from the deepest visible ancestor.
- `--output-format json` no longer corrupts braces via `fmt` (`{{` / `}}` escape).

### Changed

- Post-edit verify is off by default (`NULLRAY_VERIFY` unset). Opt in with `/verify on`, `NULLRAY_VERIFY=1`, or an explicit command.
- Verify runs through the session tools registry (fixes `unknown tool: run_shell`).
- Live tool activity in status bar and transcript (`run` line with spinner and args).
- Slash suggestions show usage (for example `/new [NAME]`) and arg hints while typing.
- Diff-aware review findings, optional `NULLRAY_RUBRIC`, deterministic controller hints, `compact_context` tool.
- `/status` for mode, plan, verify, and input char budget.
- Initial public release of nullray, an Odin TUI coding agent with Landlock/seccomp sandboxing.
- OpenAI and OpenAI-compatible providers, plus Ollama, LM Studio, OpenRouter, and OpenCode.
- Cerebras, Cohere, NVIDIA, and DashScope (Qwen) OpenAI-compat providers.
- Provider aliases: qwen/alibaba, nim/nvidia-nim, co.
- MCP handshake negotiation across protocol versions `2024-10-07` through `2025-11-25`.
- Native tool loop, sessions, MCP autoload, shell completions, and man page.
- Hardened GitHub Actions CI and tag-driven releases with generated notes.
- Release SBOMs (CycloneDX and SPDX) attached to GitHub releases, with sha256 rows in notes.md for every binary asset.
- Flatpak bundle (`io.github.Quad4_Software.nullray`, Freedesktop 25.08) and type-2 AppImage (FUSE3 runtime) on tag releases.
- Multi-stage rootless Dockerfile on digest-pinned Debian trixie-slim, docker-compose terminal attach, and GHCR publish workflow.
- Headless `--print` agent path with ask/plan/review/edit modes and plan `.md` artifacts.
- Cross-platform print CI workflow (Linux, macOS, Windows) plus print-smoke scripts.
- Session CLI: `--list-sessions`, `--search-sessions`, `--delete-session`, `--export-session` / `--import-session`, exit resume hint, and `/delete`.
- Default models refreshed for current API catalogs (OpenAI gpt-5.4-mini, Anthropic claude-sonnet-5, Gemini 3.8 Flash, Groq Qwen3.6, DeepSeek V4 Flash, xAI grok-build, and related hosts).
- Reasoning and thinking request shapes are provider-aware (OpenRouter nested effort, Cohere clamp, DeepSeek thinking toggle, DashScope enable_thinking, flat reasoning_effort elsewhere).
- Responses and streams read reasoning_content and thinking alongside reasoning / reasoning_details.
- Assistant reasoning is echoed on later turns (required for DeepSeek tool loops).
- Rate-limit and payment error text is OpenRouter-specific only when that provider is active.
- `--session NAME` resolves to `~/.config/nullray/sessions/<name>.jsonl` (raw paths still accepted when they look like files).
- Splash dismisses on any key or mouse (timer still applies if untouched).
- Unknown slash commands stay local (`unknown command: /foo · type ?`) instead of going to the model.
- Pending shell ask shows in the status bar; `/allow` and `/deny` work while the agent is busy.
- Help overlay scrolls with Page Up/Down (also Up/Down and mouse wheel).
- Splash ink uses UTF-8 full block where the terminal looks capable, ASCII `#` on limited/legacy TERM.
- Splash shows slogan Simple, Lightweight, Fast and dim version text.
- TUI setup wizard (`/setup`): provider pick, prefilled base URL and key, model list, reasoning. Writes `~/.config/nullray/env` and `NULLRAY_SETUP_DONE`. TUI-only (skipped for `--print`, `--self-test`, CI).
- Auto-detect live Ollama and LM Studio during setup. OpenRouter model catalog can carry reasoning metadata for effort defaults.
