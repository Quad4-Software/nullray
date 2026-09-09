# Agent notes for nullray

Odin coding agent with a custom TUI. Library under nullray/. CLI entry cmd/nullray. Collection: -collection:nullray=nullray.

Verify: make test

Bootstrap: plan mode Done Contract (Steps, Verify, Success, Budget), then /approve or --plan-in, then scaffold packs via list_scaffolds if the tree is empty, then verify with NULLRAY_VERIFY=1. Prefer numbered Steps. Incomplete plans get a repair nudge and are not saved.

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

nullray loads flat *.md and nested name/SKILL.md from workspace .agents/skills, .agents, config skills (~/.config/nullray/skills), and ~/.agents. Extra roots: NULLRAY_SKILLS or --skills (comma-separated). Install into config: --install-skill PATH [--as ID]. Remove: --uninstall-skill ID. List: --list-skills or /skills.

## Layout

| Path | Role |
|------|------|
| nullray/agent | Tool loop, modes, prompt, review, improve |
| nullray/app | TUI app shell, splash, slash registry, owns tools+mcp |
| nullray/config | Key binds from keys.ini |
| nullray/constants | Env keys, defaults, limits |
| nullray/crash | Signal handlers, crash dumps, --doctor / --debug |
| nullray/http | HTTP/2 (ALPN) then HTTP/1.1 JSON helpers over sockets, static Mbed TLS, and nghttp2 |
| nullray/mcp | MCP client (stdio JSON-RPC), App-owned registry |
| nullray/provider | Registry, chat, and Provider.stream |
| nullray/run | Headless --print agent runner |
| nullray/sandbox | Landlock, seccomp, secrets, redaction, ops profiles |
| nullray/elevate | Elevated auth: classify, askpass, broker, circuit |
| nullray/hooks | hooks.json PreToolUse and session lifecycle |
| nullray/memory | Project memory under `.nullray/memory` |
| nullray/vcs | Local and gated network Git/Fossil tools |
| nullray/secure | Dockerfile/compose/actions/OWASP/deps audits |
| nullray/subagent | Roster, knowledge, leases, worktrees, model policy, spawn |
| nullray/session | Live session, jobs, memory trim |
| nullray/skills | Skill file loader |
| nullray/store | Session JSONL, locks, paths |
| nullray/tools | Tool registry with kinds, shell perms |
| nullray/ui | Terminal, buffer, keys |
| cmd/nullray | Binary |
| cmd/nullray_chat_smoke | One-turn provider smoke |
| packaging/flatpak | Flatpak manifest and desktop/metainfo |
| packaging/appimage | Slim and SDK AppImage AppRun, desktop, tools.manifest |
| packaging/odin-pin | Pinned Odin commit for CI, Docker, SDK |
| web | GitHub Pages site (index.html, CNAME) + Dockerfile for self-host (busybox httpd, rootless, ~2.5MB) |
| install.sh | POSIX installer, served at /install by pages.yml |
| Dockerfile | Multi-stage rootless image (Debian trixie) |
| docker-compose.yml | Interactive terminal attach |

Project maps: .agents/references/layout.md, providers.md, footguns.md.

Project memory: AGENTS.md holds standing instructions you maintain. `.nullray/memory` holds learned observations the agent writes (keys, JSONL, MEMORY.md index, optional topics/). Keep values short. Use topic files for long notes, not huge docs in AGENTS.md. Sandbox capabilities and security claim limits are in .agents/references/sandbox.md and caveats.md. TUI file map: tui skill references/map.md.

## Build and test

```
make
make test
```

Verify: make test

make test runs odin test on ui, agent, tools, skills, session, store, sandbox, mcp, provider, patch, http, and related packages with -define:ODIN_TEST_THREADS=1, then --self-test, chat-smoke, and print-smoke. Prefer that define by hand too. Binary: bin/nullray. Needs Odin and a C compiler (builds lib/libnullray_tls.a from vendor/mbedtls, vendor/nghttp2, and vendor/mlkem-native). On Linux amd64 the archive is about 1.2 MB and a stripped binary about 3.8 MB. HTTPS prefers HTTP/2 when ALPN selects h2, else HTTP/1.1. TLS 1.2 and 1.3 with X25519MLKEM768 hybrid PQ key agreement. System CAs via SSL_CERT_FILE / SSL_CERT_DIR, then platform paths. HTTP(S)_PROXY / ALL_PROXY / NO_PROXY are honored (CONNECT for HTTPS).

Suite layers: package unit tests (adversarial focus in sandbox and tools/shell), headless --self-test, print-smoke (no provider), optional chat-smoke. Local coverage: make coverage (needs kcov) writes HTML under coverage/.

Modes: ask, plan, review, edit. Tool gate: `--gate` / `NULLRAY_GATE` / `/gate` 0..3 (ask|allow|yolo aliases). Vuln hunts: NULLRAY_HUNT / --hunt / /hunt. auto (default --hunt) runs explore then oracle in print mode. Static presets: balanced|explore|oracle|adversarial (NULLRAY_TEMPERATURE / NULLRAY_TOP_P override). Print mode: nullray --print (no TUI). Plan mode writes .md under .nullray/plans/ or --plan-out. Done Contract needs Steps, Verify, Success, and Budget (incomplete plans skip --plan-out). Apply with --plan-in / NULLRAY_PLAN_IN (headless auto-approves into edit, empty prompt becomes Execute the approved plan). Post-edit verify is off by default. Opt in with NULLRAY_VERIFY=1, /verify on, or NULLRAY_VERIFY=<cmd>. When on, uses plan Verify, AGENTS Verify, or make test. Failed verify nudges list parsed path:line findings and may offload the full log to an artifact (read_artifact / grep_artifact). Print exit: --print-strict / NULLRAY_PRINT_STRICT fails incomplete plan, verify_failed, max_steps/loop/timeout, living subagents, and tool-only writes with verify on. Session metrics: .usage.jsonl + meta summary, /usage, --usage / NULLRAY_PRINT_USAGE. Cost only when the provider sends it (never invent from /credits). NULLRAY_USAGE=0 disables persist. Ephemeral needs NULLRAY_USAGE_PERSIST=1 to write usage.

## Skills (read before editing)

| Skill | When |
|-------|------|
| prose | docs, comments, AGENTS, commit text (detail in skill references/tells.md) |
| changelog | CHANGELOG.md and release notes (user-facing, no internals) |
| tui | nullray/ui, app, binds, draw/input (map in skill references/map.md) |
| odin-idioms | any .odin under nullray/ or cmd/ |
| memory | owned strings, dynamics, teardown |
| ci-pinned-actions | .github/workflows |
| scaffold | secure templates, list_scaffolds, packs under share/nullray/scaffolds |
| greenfield | empty-repo bootstrap, Done Contract before edit |
| owasp | security review, secrets, injection, authz |
| bug-hunting | vuln/crash hunting: audit_*, oracles, exploratory, adversarial, NULLRAY_HUNT |

## Providers

Built-ins in nullray/provider/builtins.odin wrap openai_chat / openai_list_models / openai_embed (Ollama has its own list and a native /api/embed fallback). Register via registry.odin. Clone owned strings on create. provider_destroy / registry_destroy on teardown. Table: .agents/references/providers.md.

RAG (NULLRAY_RAG=auto|1|0): vectors under .nullray/rag/. NULLRAY_EMBED_PROVIDER and NULLRAY_EMBED_MODEL select the embedder (defaults: Ollama nomic-embed-text, OpenRouter openai/text-embedding-3-small). memory_put indexes when RAG is on. Tools: rag_status, rag_query, rag_reindex. Artifact bodies may be indexed unless NULLRAY_RAG_ARTIFACTS=0.

## Sandbox

Linux Landlock and seccomp in nullray/sandbox/. Non-Linux: sandbox_stub.odin (#+build !linux). Soft/Warn skips with a warn on other OS. Strict fails with sandbox requires linux.

Elevated commands (sudo/doas/pkexec) use nullray/elevate with a pre-sandbox privilege broker. Landlock sets NO_NEW_PRIVS, so in-process sudo cannot gain privileges. Passwords stay on the TUI askpass path and never enter tool results or provider messages. NULLRAY_ELEVATE=ask|deny|ticket. Headless: ticket or NULLRAY_ASKPASS.

Ops profiles: NULLRAY_OPS=desktop|docker|kube|full (CSV). Prefer over NULLRAY_SANDBOX=off. EXTRA_RO/RW for absolute paths. NULLRAY_DOCS (default on) adds narrow RO grants for tldr/rustup host caches. VCS network: NULLRAY_VCS_NETWORK=1.

## Terminal

Platform backends: ui/term_linux.odin, ui/term_bsd.odin, ui/term_windows.odin. Key ready: keys_unix.odin / keys_windows.odin. Paint cells only. ANSI in term_present. Details: tui skill.

## Config

Default root: ~/.config/nullray/ (XDG on Unix). Files: env, keys.ini, mcp.json, sessions/ (`.msgpack` default, `.jsonl` fallback). Rename with `/name` or `--rename-session`.

LID harness (wave 1): tool dumps above NULLRAY_ARTIFACT_CHARS (default 3000) go to .nullray/artifacts/ and the model sees status/path/artifact/excerpt envelopes. Peek with read_artifact / grep_artifact (default line cap NULLRAY_ARTIFACT_READ_LINES=200, hard 32KB). Provider history is a projection (NULLRAY_PROJECTION_TURNS / NULLRAY_PROJECTION_TOOL_STUBS). NULLRAY_LID=0 disables projection, artifact store, and phase reset (envelopes stay, without artifact=). NULLRAY_PROMPT=lean|full|auto (auto under print) ships a compact tools JSON core set that still includes read_man/apropos/read_tldr/read_info/read_help/lang_doc/fetch_url, and a small subagent subset (task/agents_*/knowledge_*) when subagents are on. Metrics: NULLRAY_HARNESS_METRICS=1 or NULLRAY_DEBUG=1, also harness_* fields in .usage.jsonl (including harness_tools_json). TUI stubs artifact tool rows; expand with /artifact ID. Artifact GC runs on session destroy and --doctor (64MB / 7 day sweep).

Speculative tools (on by default): set NULLRAY_SPECULATE=0 to disable. Pre-runs allowlisted read-only tools once a streamed tool_calls index is sealed (next index or stream end), and parallelizes a leading read-only prefix after the response. Cap with NULLRAY_SPECULATE_PARALLEL (default 2). Writes, shell, compact_context, task, and fetch_url never speculate. Handoff matches on tool id, name, and args hash. Misses fall back to the serial path. LID offload and PostToolUse run only on handoff.

Key presets: default, neovim, emacs (preset= in keys.ini), or NULLRAY_KEYS / --keys.

Splash defaults on. Off: NULLRAY_SPLASH=0 (also false/off/no/disable) or --no-splash. Force: --splash or NULLRAY_SPLASH=1.

View pane auto-opens the last write path after a turn. Off: NULLRAY_VIEW_AUTO=0 or `/view auto off`.

Terminals: NULLRAY_COLOR=none|16|256|true. TERM=dumb / empty skips mouse and alt-screen (NULLRAY_MOUSE / NULLRAY_ALT_SCREEN override). WSL uses COLUMNS/LINES when ioctl size is 0. NO_COLOR disables color.

Crash dumps land in ~/.config/nullray/crashes/ on fatal signals and asserts. --doctor prints env and the latest dump path. --debug / NULLRAY_DEBUG=1 logs lifecycle on stderr. make debug builds with symbols for richer backtraces.

OpenRouter: retries on 429/502/503 (NULLRAY_HTTP_RETRIES). NULLRAY_FALLBACK_MODELS and NULLRAY_OPENROUTER_IGNORE for provider routing. NULLRAY_PROVIDER_FALLBACKS=ollama,groq,... tries other providers on chat auth/payment failure. OPENROUTER_CREDITS_KEY optional for /credits. HTTP(S)_PROXY / ALL_PROXY / NO_PROXY honored for outbound HTTPS CONNECT. NULLRAY_AGENT_TOOLS=0 disables tool schemas in print/TUI (needed for local models that reject tools).

## Subagents

Package nullray/subagent. Tools: task, agents_status/peek/progress/wait/verify, knowledge_*, model_use, board_*, send_message/read_messages.

- Cap: NULLRAY_SUBAGENTS (default 3). Zero or /agents off / --no-subagents disables task.
- Depth: NULLRAY_SUBAGENT_DEPTH (default 1).
- Models: ~/.config/nullray/models.json and .nullray/models.json. /model lock freezes switches. Roles explore/edit/review/verify. For local setups, map explore (and plan/architect work) to a fast local model and edit/verify to a stronger one.
- Isolation: shared + path leases for explore. Worktrees under .nullray/worktrees/ for edit. Never auto git stash.
- Join with agents_wait, then agents_verify before /agents apply. Peer messaging needs NULLRAY_SUBAGENT_TEAMS=1.
- Locate: `task` with `subagent_type=locate` returns a CITES block of workspace-relative `path:start-end` spans. Hard step budget NULLRAY_LOCATE_STEPS (default 4, max 8). In-child speculate parallel NULLRAY_LOCATE_PARALLEL (default 8). Cap cites with NULLRAY_LOCATE_MAX_CITES (default 12). Tools allowlisted to repo_map, glob_files, grep_files, read_file, list_dir. Shared isolation only. Prefer sync task. Optional path_hints and max_steps on task.
- Architect: `task` with `subagent_type=architect` returns a Done Contract for the parent. Hard step budget NULLRAY_ARCHITECT_STEPS (default 6, max 8). Tools allowlisted to locate set plus list_scaffolds. Ask mode, shared isolation. Child does not save the parent plan file.

## CI

Workflows under .github/workflows/.

- `ci.yml`: package tests (Linux) plus build/self-test/print-smoke on Linux, macOS, Windows
- `print.yml`: dedicated print-mode smoke on Linux, macOS, Windows (optional live `--print` when OPENROUTER_API_KEY is set)
- `pages.yml`: deploys web/ to GitHub Pages on push to master, stages install.sh at /install. Custom domain nullray.xyz via web/CNAME, DNS on Bunny (CNAME to quad4-software.github.io)
- Pin every third-party action to a full commit SHA with a version comment
- First step of every job: step-security/harden-runner
- No pull_request_target
- Bump tag and SHA together. Dependabot covers github-actions weekly
- Releases immutable (v*.*.* tags). Cut a new patch instead of moving a tag

Skill: ci-pinned-actions. Scripts: scripts/print-smoke.sh, scripts/print-smoke.ps1.

## Memory

Clone strings you own. Delete in matching destroy procs. Prefer context.temp_allocator for short-lived parse and path work. Skills: memory, odin-idioms. Traps: .agents/references/footguns.md.
