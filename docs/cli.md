# CLI reference

`nullray --help` prints the flags below at runtime. This page groups
them by what they do.

## General

| Flag | Purpose |
|------|---------|
| `-h`, `--help` | Help and exit |
| `-V`, `--version` | Version and build stamp |
| `-e`, `--ephemeral` | Do not load or save transcripts |
| `-t`, `--self-test` | Headless smoke checks and exit |
| `--doctor` | Config paths, env, TTY, crash dump |
| `--debug` | Verbose stderr lifecycle logs |
| `--audit` | Workspace security scanners, exit 1 on highs |
| `--man` | Print man page source |
| `--completions SHELL` | bash, zsh, fish, powershell, elvish, nushell |

## Provider and model

| Flag | Purpose |
|------|---------|
| `-p`, `--provider ID` | Provider id, see [providers](providers.md) |
| `-m`, `--model NAME` | Override the model |
| `--list-models` | Print catalog for the active provider (falls back to the models.dev cache) |
| `--theme NAME` | ink, ember, moss, slate, rose, mono, dusk |
| `--keys PRESET` | default, neovim, emacs |

## Agent behavior

| Flag | Purpose |
|------|---------|
| `--mode MODE` | ask, plan, review, edit, orchestrate |
| `--hunt [PROFILE]` | Vuln hunt: auto, balanced, explore, oracle, adversarial |
| `--perms POLICY` | ask, allow, yolo |
| `--gate LEVEL` | 0..3, or ask, allow, yolo aliases |
| `--sandbox MODE` | off, soft, warn, strict, on |
| `--auto` | Autonomous edit: yolo, 80 steps, verify on |
| `--no-elevate` | Deny elevated commands |
| `-w`, `--workspace PATH` | Workspace root |

## Print mode

`--print` runs one turn without the TUI, prints the reply, and exits.
Defaults: ephemeral session, ask mode. The prompt comes from trailing
arguments, `--message-file PATH`, or stdin when it is not a TTY.

| Flag | Purpose |
|------|---------|
| `-P`, `--print` | One-shot agent turn |
| `-q`, `--ask` | Print + ask + ephemeral, read-only |
| `--message-file PATH` | Prompt text from a file |
| `--image/--audio/--video/--media PATH` | Attach media, repeatable |
| `--out PATH` | Write the reply to a file |
| `--plan-out PATH` | Write the plan artifact |
| `--plan-in PATH` | Apply a Done Contract into edit |
| `--output-format text\|json` | Reply format |
| `--print-strict` | Exit 1 on incomplete plan, verify failure, step cap, loop, timeout, or living subagents |
| `--stream` | Stream reply tokens to stdout live (print mode) |
| `--trace` | One stderr line per tool call with elapsed time and exit code |
| `--patch-out PATH` | Write a unified diff of everything the run changed |
| `--no-adopt` | Skip foreign config/key adoption for this run |
| `--fail-on-findings` | Exit 1 when review ends `FINDINGS: N`, N > 0 |
| `--usage` | Print token and cost summary |
| `--samples N` | Best-of-N print runs in git worktrees, pick by the verifier |
| `--architect` | Architect model writes a Done Contract, then the editor model executes it |
| `--timeout SEC` | Wall clock limit, default 600 |

## ACP server

`--acp` runs the Agent Client Protocol v1 server over stdio (newline-delimited
JSON-RPC) so editors such as Zed can drive nullray as their agent. stdout
carries protocol messages only. logs go to stderr. Modes map to ACP session
modes, including orchestrate.

| Flag | Purpose |
|------|---------|
| `--acp` | ACP v1 server over stdio |

## Daemon

`nullray serve` (or `--serve`) runs a shared agent daemon on a unix socket:
`$XDG_RUNTIME_DIR/nullray/nullray.sock` by default, `NULLRAY_SERVE_SOCK` to
override. Sessions live in the daemon and survive client disconnects. 
`--print --connect` (or `NULLRAY_CONNECT`) runs a prompt through the warm
daemon instead of a cold process, and `nullray attach [SESSION]` attaches a
streaming client that can send prompts. Socket perms are 0600. there is no
TCP listener. Remote access goes over `ssh -L` forwarding.

| Flag | Purpose |
|------|---------|
| `--serve` | Run the shared daemon |
| `--connect` | Route `--print` through the daemon |
| `attach [SESSION]` | Attach to a daemon session |

## Watches

`nullray watch` manages standing watches: durable scheduled jobs that run a
check, diff the result set against `.nullray/watch/<id>/state.json`, append to
`digest.md`, and send a desktop notification only on new hits. A running daemon
picks up adds and removals on its next tick; recurring watches auto-expire
after 7 days unless `--expires` overrides.

| Command | Purpose |
|---------|---------|
| `watch add <spec> <instruction>` | Add a watch. Spec: `2h`, `every 2h`, `at 09:00`, or 5-field cron |
| `watch list` / `watch status` | List watches with next fire, expiry, run counts, tokens |
| `watch show <id>` | Watch state plus the digest tail |
| `watch rm <id>` | Remove a watch and its state |

`watch add` flags: `--max-runs N` caps firings, `--max-tokens N` cancels the
watch once cumulative daemon turn tokens pass the cap, `--expires DUR` sets a
lifetime like `7d`.

## Review bot

`--review` reviews a local diff and exits. No forge needed.

| Flag | Purpose |
|------|---------|
| `--review` | Run the review bot |
| `--review-scope S` | working, staged, unstaged, base |
| `--base REF` | Review against a branch or revision |
| `--staged`, `--unstaged` | Index or working-tree diffs |
| `--include-untracked` | Include untracked files |
| `--paths LIST` | Comma-separated path filters |

## Sessions

| Flag | Purpose |
|------|---------|
| `--session NAME` | Resume or create a named session |
| `--list-sessions` | List saved sessions |
| `--inspect-session [NAME]` | Summary, `--follow` tails updates |
| `--search-sessions Q` | Search names, metadata, transcript |
| `--delete-session N` | Delete a session |
| `--rename-session N` | Rename, needs `--as NEW` |
| `--export-session N` | Copy transcript and meta to `--out DIR` |
| `--import-session P` | Import a .jsonl or its directory |
| `--as NAME` | Destination name for import/rename |
| `--force` | Overwrite destination on rename |

## Skills

| Flag | Purpose |
|------|---------|
| `--list-skills` | Loaded skills: id, description, source |
| `--skills PATH` | Extra skill roots, comma-separated, repeatable |
| `--bare` | Skip home MCP and non-workspace skills |

## Misc

| Flag | Purpose |
|------|---------|
| `--no-splash`, `--splash` | Skip or force the startup splash |
| `--no-subagents` | Disable the task tool |
| `--hide-sensitive` | Hide account and API key balances |
| `--askpass` | sudo/doas askpass helper (internal) |
| `--elevate-broker P` | Privilege broker path (internal) |

## TUI

`/history` inside the TUI opens a scrollable full session history that
includes thinking and reasoning text (dimmed). Scroll with Up/Down,
PageUp/PageDown, or the mouse wheel, Home/End jump, Esc closes.

## Exit notes

Print mode exits 0 on a completed reply. `--print-strict` and
`--fail-on-findings` add failure exits. `--audit` exits 1 on high
findings. Abnormal signals drop a crash dump under
`~/.config/nullray/crashes/`.
