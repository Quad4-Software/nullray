# Agent notes for nullray

Odin coding agent with a custom TUI. Library under nullray/. CLI entry cmd/nullray. Collection: -collection:nullray=nullray.

## Layout

| Path | Role |
|------|------|
| nullray/agent | Tool loop, modes, prompt, review, improve |
| nullray/app | TUI app shell, splash, slash commands |
| nullray/config | Key binds from keys.ini |
| nullray/constants | Env keys, defaults, limits |
| nullray/http | libcurl JSON helpers |
| nullray/mcp | MCP client (stdio JSON-RPC) |
| nullray/provider | Registry and Chat Completions clients |
| nullray/sandbox | Landlock, seccomp, secrets, redaction |
| nullray/session | Live session, jobs, memory trim |
| nullray/skills | Skill file loader |
| nullray/store | Session JSONL, locks, paths |
| nullray/tools | Agent tools and shell perms |
| nullray/ui | Terminal, buffer, keys |
| cmd/nullray | Binary |
| cmd/nullray_chat_smoke | One-turn provider smoke |

Maps: `.agents/references/layout.md`, `tui.md`, `providers.md`, `footguns.md`.

## Build and test

```
make
make test
```

make test runs odin test on ui, agent, tools, store, sandbox, mcp, and provider with -define:ODIN_TEST_THREADS=1, then --self-test and chat-smoke. Prefer that define by hand too. Binary: bin/nullray. Needs Odin and libcurl.

## Skills (read before editing)

| Skill | When |
|-------|------|
| prose | docs, comments, AGENTS, commit text |
| tui | nullray/ui, app, binds, draw/input |
| odin-idioms | any .odin under nullray/ or cmd/ |
| memory | owned strings, dynamics, teardown |
| ci-pinned-actions | .github/workflows |

## Providers

Built-ins in nullray/provider/builtins.odin wrap openai_chat / openai_list_models (Ollama has its own list). Register via registry.odin. Clone owned strings on create. provider_destroy / registry_destroy on teardown. Table: `.agents/references/providers.md`.

## Sandbox

Linux Landlock and seccomp in nullray/sandbox/. Non-Linux: sandbox_stub.odin (#+build !linux). Soft/Warn skips with a warn on other OS. Strict fails with sandbox requires linux.

## Terminal

Platform backends: ui/term_linux.odin, ui/term_bsd.odin, ui/term_windows.odin. Key ready: keys_unix.odin / keys_windows.odin. Paint cells only. ANSI in term_present. Details: tui skill + references/tui.md.

## Config

Default root: ~/.config/nullray/ (XDG on Unix). Files: env, keys.ini, mcp.json, sessions/.

Key presets: default, neovim, emacs (preset= in keys.ini), or NULLRAY_KEYS / --keys.

Splash defaults on. Off: NULLRAY_SPLASH=0 (also false/off/no/disable) or --no-splash. Force: --splash or NULLRAY_SPLASH=1.

## CI

Workflows under .github/workflows/.

- Pin every third-party action to a full commit SHA with a version comment
- First step of every job: step-security/harden-runner
- No pull_request_target
- Bump tag and SHA together. Dependabot covers github-actions weekly
- Releases immutable (v*.*.* tags). Cut a new patch instead of moving a tag

Skill: `.agents/skills/ci-pinned-actions/SKILL.md`.

## Memory

Clone strings you own. Delete in matching destroy procs. Prefer context.temp_allocator for short-lived parse and path work. Skills: memory, odin-idioms. Traps: `.agents/references/footguns.md`.
