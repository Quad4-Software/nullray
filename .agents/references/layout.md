# Repository layout

```
cmd/
  nullray/              CLI main, flags, completions, man text
  nullray_chat_smoke/   One-turn chat smoke binary
nullray/
  agent/                Multi-step tool loop, parse, compact, mode, review, improve
  app/                  App state, draw, input, splash, slash commands
  config/               keys.ini load and presets
  constants/            Shared env names, defaults, limits
  http/                 libcurl helpers
  mcp/                  MCP JSON-RPC and stdio client
  provider/             Registry, builtins, openai_chat wrappers, streaming
  sandbox/              Landlock/seccomp (Linux), stub elsewhere, secrets, redact
  selftest/             Headless --self-test checks
  session/              Session, jobs, persist hooks, memory trim
  skills/               Skill file discovery and load
  store/                Session paths, JSONL transcript, locks, meta
  tools/                Tool registry, fs/grep/glob/shell/script, perms
  ui/                   Terminal backends, buffer, keys, markdown
.github/workflows/      ci, release, dependency-review, codeql
.agents/
  skills/               prose, tui, odin-idioms, memory, ci-pinned-actions
  references/           layout, providers, tui, footguns
contrib/completions/    Shell completion scripts
man/                    nullray.1
logo/                   Brand assets
scripts/                Logo generator, release notes
```

Build:

```
make
```

Output: bin/nullray via -collection:nullray=$(ROOT)/nullray.

## Agent docs

| Path | Role |
|------|------|
| references/layout.md | this map |
| references/providers.md | provider ids and env keys |
| references/tui.md | ui/app/config file map |
| references/footguns.md | hard never-dos and ownership traps |
| skills/prose/ | docs and comment style |
| skills/tui/ | cell buffer, loop, keys, splash |
| skills/odin-idioms/ | packages, #+build, errors |
| skills/memory/ | destroy pairs and allocators |
| skills/ci-pinned-actions/ | workflow SHA pins |
