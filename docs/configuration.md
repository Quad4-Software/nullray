# Configuration

## Layout

Config root is `~/.config/nullray` (`$XDG_CONFIG_HOME/nullray`).

| Path | Contents |
|------|----------|
| `env` | `KEY=value` lines, one per variable |
| `keys.ini` | Key bindings and optional `preset=` line |
| `mcp.json` | MCP server autoload config |
| `sessions/` | Transcripts (`.msgpack`, `.jsonl` fallback) and metadata |
| `skills/` | User-installed skills |
| `models.json` | Subagent role to model map |
| `open_tabs` | Persisted tab layout |
| `crashes/` | Latest signal dump path shown by `--doctor` |

Workspace-local state lives under `.nullray/` in the project: plans,
artifacts, memory, RAG vectors, worktrees, hooks.json, and traces.

## Precedence

Highest wins:

1. Command line flags
2. Process environment
3. `~/.config/nullray/env`
4. Adopted foreign config, which only fills what is still unset

Foreign adoption runs once at startup before the sandbox applies.
Adopted values never write back to the env file. They live for the
process only, so nothing silently persists a borrowed credential.

## Core variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `NULLRAY_PROVIDER` | | Provider id, see [providers](providers.md) |
| `NULLRAY_MODEL` | | Model name |
| `NULLRAY_REASONING` | | Reasoning effort: low, medium, high, none |
| `NULLRAY_MODE` | edit | ask, plan, review, edit |
| `NULLRAY_PERMS` | ask | Shell policy: ask, allow, yolo |
| `NULLRAY_GATE` | | Tool capability gate 0..3 |
| `NULLRAY_SANDBOX` | warn | off, soft, warn, strict, on |
| `NULLRAY_WORKSPACE` | cwd | Workspace root for tools and sandbox |
| `NULLRAY_SESSION` | | Named session to resume or create |
| `NULLRAY_EPHEMERAL` | | Do not save transcripts |
| `NULLRAY_STREAM` | on | Stream replies |
| `NULLRAY_TEMPERATURE` | | Sampling override |
| `NULLRAY_TOP_P` | | Sampling override |
| `NULLRAY_AUTO` | | Autonomous edit, see modes |
| `NULLRAY_HUNT` | | Vuln hunt profile |
| `NULLRAY_ADOPT` | 1 | Foreign config adoption |

## Terminal and UI

| Variable | Purpose |
|----------|---------|
| `NULLRAY_THEME` | ink, ember, moss, slate, rose, mono, dusk |
| `NULLRAY_KEYS` | Key preset: default, neovim, emacs |
| `NULLRAY_SPLASH` | Startup splash on/off |
| `NULLRAY_COLOR` | none, 16, 256, true |
| `NULLRAY_ALT_SCREEN` | Alternate screen buffer |
| `NULLRAY_MOUSE` | Mouse input |
| `NULLRAY_VIEW_AUTO` | Auto-open view pane on writes |
| `NULLRAY_NOTIFY` | auto, desktop, osc, bell, off |
| `NULLRAY_BARE` | Skip home MCP and non-workspace skills |
| `NULLRAY_HIDE_SENSITIVE` | Hide balances and credit labels |

## Harness

| Variable | Purpose |
|----------|---------|
| `NULLRAY_PROMPT` | lean, full, auto tool prompt |
| `NULLRAY_LID` | Artifact store and projection (0 disables) |
| `NULLRAY_ARTIFACT_CHARS` | Tool dump threshold, default 3000 |
| `NULLRAY_ARTIFACT_READ_LINES` | Default peek lines, default 200 |
| `NULLRAY_SPECULATE` | Speculative read-only tool runs |
| `NULLRAY_SPECULATE_PARALLEL` | Speculation cap, default 2 |
| `NULLRAY_AGENT_TOOLS` | 0 drops tool schemas entirely |
| `NULLRAY_VERIFY` | Post-edit verify gate |
| `NULLRAY_PRINT_TIMEOUT` | Print wall clock, default 600s |
| `NULLRAY_PRINT_STRICT` | Exit 1 on incomplete runs |
| `NULLRAY_PRINT_USAGE` | Print token and cost summary |
| `NULLRAY_RECALL` | Scoped memory recall (0 disables) |
| `NULLRAY_MEDIA` | Media attachments (0 disables) |
| `NULLRAY_MEDIA_MAX` | Per-file cap, default 15 MB |
| `NULLRAY_MEDIA_TURNS` | Resend window, default 2 |

## Sandbox and operations

| Variable | Purpose |
|----------|---------|
| `NULLRAY_OPS` | CSV profiles: desktop, docker, kube, full |
| `NULLRAY_SANDBOX_EXTRA_RO` | Extra read-only absolute paths |
| `NULLRAY_SANDBOX_EXTRA_RW` | Extra read-write absolute paths |
| `NULLRAY_DOCS` | Narrow RO for doc caches (tldr, rustup) |
| `NULLRAY_TOOLCHAIN` | Narrow RW for Go/Cargo/npm caches |
| `NULLRAY_ELEVATE` | ask, deny, ticket |
| `NULLRAY_ASKPASS` | External askpass helper path |
| `NULLRAY_SECRETS_ALLOW` | Absolute paths allowed to read secrets |
| `NULLRAY_VCS_NETWORK` | Enable vcs_push/pull/fetch/PR tools |
| `NULLRAY_VCS_FORCE` | Allow force-push to main/master |

## Foreign adoption control

`NULLRAY_ADOPT=0` turns off detection entirely. There is no finer
switch because adoption never overwrites set values anyway: exporting a
variable beats adoption, so a stray foreign config can only fill gaps.

## Foreign config and MCP

`mcp.json` holds MCP server autoload entries. Workspace hooks live in
`.nullray/hooks.json`. See [skills and MCP](skills-mcp.md) and
[security](security.md).
