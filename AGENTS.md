# Agent notes for nullray

Odin coding agent with a custom TUI. Library code lives under `nullray/`. The CLI entry is `cmd/nullray`. Collection flag: `-collection:nullray=nullray`.

## Layout

| Path | Role |
|------|------|
| `nullray/agent` | Tool loop, modes, prompt, review, improve |
| `nullray/app` | TUI app shell, splash, slash commands |
| `nullray/config` | Key binds from keys.ini |
| `nullray/constants` | Env keys, defaults, limits |
| `nullray/http` | libcurl JSON helpers |
| `nullray/mcp` | MCP client (stdio JSON-RPC) |
| `nullray/provider` | Registry and Chat Completions clients |
| `nullray/sandbox` | Landlock, seccomp, secrets, redaction |
| `nullray/session` | Live session, jobs, memory trim |
| `nullray/skills` | Skill file loader |
| `nullray/store` | Session JSONL, locks, paths |
| `nullray/tools` | Agent tools and shell perms |
| `nullray/ui` | Terminal, buffer, keys |
| `cmd/nullray` | Binary |
| `cmd/nullray_chat_smoke` | One-turn provider smoke |

Full map: `.agents/references/layout.md`. Provider ids and env keys: `.agents/references/providers.md`.

## Build and test

```sh
make
make test
```

`make test` runs `odin test` on ui, agent, tools, store, sandbox, mcp, and provider with `-define:ODIN_TEST_THREADS=1`, then `--self-test` and chat-smoke. Prefer that define when invoking `odin test` by hand. Output binary: `bin/nullray`. Needs Odin and libcurl.

## Providers

Built-ins in `nullray/provider/builtins.odin` wrap `openai_chat` / `openai_list_models` (Ollama uses its own list). Register and select via `registry.odin`. Clone owned strings on create. Call `provider_destroy` / `registry_destroy` on teardown.

## Sandbox

Linux Landlock and seccomp live in `nullray/sandbox/`. Non-Linux builds use `sandbox_stub.odin` (`#+build !linux`). Soft mode skips with a warn on other OS. Strict mode fails with "sandbox requires linux".

## Terminal

Platform term backends: `ui/term_linux.odin`, `ui/term_bsd.odin` (Darwin and BSD), `ui/term_windows.odin`. Key decode splits `keys_unix.odin` / `keys_windows.odin`.

## Config

Default config root: `~/.config/nullray/` (XDG on Unix). Common files: `env`, `keys.ini`, `mcp.json`, `sessions/`.

Key presets: `default`, `neovim`, `emacs` in `keys.ini` (`preset=`), or override with `NULLRAY_KEYS` / `--keys`.

Splash defaults on. Disable with `NULLRAY_SPLASH=0` (also false/off/no/disable) or `--no-splash`. Force with `--splash` or `NULLRAY_SPLASH=1`.

## CI

Workflows under `.github/workflows/`. Rules:

- Pin every third-party action to a full commit SHA with a version comment (`uses: org/action@<40-char-sha> # vX.Y.Z`).
- First step of every job: step-security/harden-runner.
- No `pull_request_target`.
- Bump tag and SHA together. Dependabot covers github-actions weekly.
- Releases are immutable (`v*.*.*` tags). Cut a new patch instead of moving a tag.

Skill: `.agents/skills/ci-pinned-actions/SKILL.md`.

## Memory

Clone strings you own. Delete them in matching destroy procs. Prefer `context.temp_allocator` for short-lived parse and path work. Skills: `.agents/skills/memory/SKILL.md`, `.agents/skills/odin-idioms/SKILL.md`.
