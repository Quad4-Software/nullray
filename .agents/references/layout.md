# Repository layout

```
cmd/
  nullray/              CLI main, flags, completions, man text
  nullray_chat_smoke/   One-turn chat smoke binary
nullray/
  agent/                Multi-step tool loop, parse, compact, mode, review, improve
  app/                  App state, draw, input, splash, slash command registry
  config/               keys.ini load and presets
  constants/            Shared env names, defaults, limits
  crash/                Fatal signals, crash dumps, doctor, debug log
  http/                 libcurl helpers
  mcp/                  MCP JSON-RPC and stdio client (owned by App)
  provider/             Registry, builtins, openai_chat wrappers, streaming via Provider.stream
  run/                  Headless --print agent (no TUI)
  sandbox/              Landlock/seccomp (Linux), stub elsewhere, secrets, redact
  selftest/             Headless --self-test checks
  session/              Session, jobs, persist hooks, memory trim
  skills/               Skill file discovery and load
  store/                Session paths, JSONL transcript, locks, meta
  tools/                Tool registry with kinds, fs/grep/glob/shell/script, perms
  ui/                   Terminal backends, buffer, keys, markdown
.github/workflows/      ci, print (linux/macos/windows), release, docker/GHCR, dependency-review, codeql
.github/workflows/examples/  Optional sample workflows (not default CI)
AGENTS.md               Ambient agent notes (portable)
.agents/
  skills/<name>/SKILL.md
  skills/<name>/references/   Skill-local detail (Agent Skills layout)
  references/                 Shared project maps (via AGENTS.md)
contrib/completions/    Shell completion scripts
man/                    nullray.1
logo/                   Brand assets
packaging/
  flatpak/              Flatpak manifest, desktop, metainfo
  appimage/             AppImage desktop entry
Dockerfile              Multi-stage rootless Debian trixie image
docker-compose.yml      Interactive terminal attach
scripts/                Logo generator, release notes, AppImage/Flatpak builders
```

Build:

```
make
```

Output: bin/nullray via -collection:nullray=$(ROOT)/nullray.

## Agent docs

| Path | Role |
|------|------|
| AGENTS.md | Ambient project facts |
| references/layout.md | this map |
| references/providers.md | provider ids and env keys |
| references/footguns.md | hard never-dos and ownership traps |
| skills/prose/ | docs and comment style |
| skills/prose/references/tells.md | 2026 prose tell detail |
| skills/tui/ | cell buffer, loop, keys, splash |
| skills/tui/references/map.md | ui/app/config file map |
| skills/odin-idioms/ | packages, #+build, errors |
| skills/memory/ | destroy pairs and allocators |
| skills/ci-pinned-actions/ | workflow SHA pins |

Skills follow Agent Skills: folder name matches frontmatter name, SKILL.md required, optional references/ scripts/ assets/. Keep skill body short. Load skill-local references on demand with paths relative to the skill root.
