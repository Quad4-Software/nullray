# Agent notes for nullray

Odin coding agent with a custom TUI. Library under nullray/. CLI entry cmd/nullray. Collection: -collection:nullray=nullray.

## Agent layout

Portable layout used by Agent Skills (agentskills.io) and most coding agents:

```
AGENTS.md                 Ambient project facts (always-on)
.agents/
  skills/<name>/SKILL.md  On-demand skills (name matches folder)
  skills/<name>/references/   Optional skill-local detail
  references/             Shared project maps (not skill packages)
```

Rules:

- Skills are directories with SKILL.md plus optional references/, scripts/, assets/
- Frontmatter name and description required. name matches the parent folder
- Skill links to its own files use paths relative to the skill root (one level deep)
- Shared maps live under .agents/references/ and are pointed from AGENTS.md
- Do not put vendor-only agent config in .agents/ (no product-specific rule dirs here)

nullray loads flat *.md and nested name/SKILL.md from workspace .agents/skills, .agents, config skills, and ~/.agents.

## Layout

| Path | Role |
|------|------|
| nullray/agent | Tool loop, modes, prompt, review, improve |
| nullray/app | TUI app shell, splash, slash registry, owns tools+mcp |
| nullray/config | Key binds from keys.ini |
| nullray/constants | Env keys, defaults, limits |
| nullray/crash | Signal handlers, crash dumps, --doctor / --debug |
| nullray/http | libcurl JSON helpers |
| nullray/mcp | MCP client (stdio JSON-RPC), App-owned registry |
| nullray/provider | Registry, chat, and Provider.stream |
| nullray/run | Headless --print agent runner |
| nullray/sandbox | Landlock, seccomp, secrets, redaction |
| nullray/session | Live session, jobs, memory trim |
| nullray/skills | Skill file loader |
| nullray/store | Session JSONL, locks, paths |
| nullray/tools | Tool registry with kinds, shell perms |
| nullray/ui | Terminal, buffer, keys |
| cmd/nullray | Binary |
| cmd/nullray_chat_smoke | One-turn provider smoke |
| packaging/flatpak | Flatpak manifest and desktop/metainfo |
| packaging/appimage | AppImage desktop entry |
| Dockerfile | Multi-stage rootless image (Debian trixie) |
| docker-compose.yml | Interactive terminal attach |

Project maps: .agents/references/layout.md, providers.md, footguns.md. TUI file map: tui skill references/map.md.

## Build and test

```
make
make test
```

make test runs odin test on ui, agent, tools, store, sandbox, mcp, and provider with -define:ODIN_TEST_THREADS=1, then --self-test, chat-smoke, and print-smoke. Prefer that define by hand too. Binary: bin/nullray. Needs Odin and libcurl.

Modes: ask, plan, review, edit. Print mode: nullray --print (no TUI). Plan mode writes .md under .nullray/plans/ or --plan-out.

## Skills (read before editing)

| Skill | When |
|-------|------|
| prose | docs, comments, AGENTS, commit text (detail in skill references/tells.md) |
| tui | nullray/ui, app, binds, draw/input (map in skill references/map.md) |
| odin-idioms | any .odin under nullray/ or cmd/ |
| memory | owned strings, dynamics, teardown |
| ci-pinned-actions | .github/workflows |

## Providers

Built-ins in nullray/provider/builtins.odin wrap openai_chat / openai_list_models (Ollama has its own list). Register via registry.odin. Clone owned strings on create. provider_destroy / registry_destroy on teardown. Table: .agents/references/providers.md.

## Sandbox

Linux Landlock and seccomp in nullray/sandbox/. Non-Linux: sandbox_stub.odin (#+build !linux). Soft/Warn skips with a warn on other OS. Strict fails with sandbox requires linux.

## Terminal

Platform backends: ui/term_linux.odin, ui/term_bsd.odin, ui/term_windows.odin. Key ready: keys_unix.odin / keys_windows.odin. Paint cells only. ANSI in term_present. Details: tui skill.

## Config

Default root: ~/.config/nullray/ (XDG on Unix). Files: env, keys.ini, mcp.json, sessions/.

Key presets: default, neovim, emacs (preset= in keys.ini), or NULLRAY_KEYS / --keys.

Splash defaults on. Off: NULLRAY_SPLASH=0 (also false/off/no/disable) or --no-splash. Force: --splash or NULLRAY_SPLASH=1.

Terminals: NULLRAY_COLOR=none|16|256|true. TERM=dumb / empty skips mouse and alt-screen (NULLRAY_MOUSE / NULLRAY_ALT_SCREEN override). WSL uses COLUMNS/LINES when ioctl size is 0. NO_COLOR disables color.

Crash dumps land in ~/.config/nullray/crashes/ on fatal signals and asserts. --doctor prints env and the latest dump path. --debug / NULLRAY_DEBUG=1 logs lifecycle on stderr. make debug builds with symbols for richer backtraces.

OpenRouter: retries on 429/502/503 (NULLRAY_HTTP_RETRIES). NULLRAY_FALLBACK_MODELS and NULLRAY_OPENROUTER_IGNORE for provider routing.

## CI

Workflows under .github/workflows/.

- `ci.yml`: package tests (Linux) plus build/self-test/print-smoke on Linux, macOS, Windows
- `print.yml`: dedicated print-mode smoke on Linux, macOS, Windows (optional live `--print` when OPENROUTER_API_KEY is set)
- Pin every third-party action to a full commit SHA with a version comment
- First step of every job: step-security/harden-runner
- No pull_request_target
- Bump tag and SHA together. Dependabot covers github-actions weekly
- Releases immutable (v*.*.* tags). Cut a new patch instead of moving a tag

Skill: ci-pinned-actions. Scripts: scripts/print-smoke.sh, scripts/print-smoke.ps1.

## Memory

Clone strings you own. Delete in matching destroy procs. Prefer context.temp_allocator for short-lived parse and path work. Skills: memory, odin-idioms. Traps: .agents/references/footguns.md.
