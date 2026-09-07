# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-07 [Unreleased]

### Added

- Progressive skills: YAML frontmatter catalog in the system prefix, `load_skill` / `list_skills`, auto-activate into the transcript (cache-safe).
- Context pipeline: tool-result clearing, wired `NULLRAY_COMPACT_CHARS` auto-compact, slim tool catalog text, lean AGENTS.md cap, `read_file` offset/limit.
- Done Contract plans (`## Verify` / `## Success` / `## Budget` / `## Failure`), `/approve`, edit-mode plan summary injection.
- Post-edit verify stop gate (`NULLRAY_VERIFY`, `/verify`) with truncated output and circuit breaker.
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
