# Modes and permissions

Three independent dials decide what the agent may do: the mode, the
tool gate, and the shell permission policy.

## Modes

| Mode | Behavior |
|------|----------|
| ask | Read-only. Answers questions, never writes files or runs commands |
| plan | Writes a Done Contract plan, no edits. Approve with `/approve` |
| review | Code review output, ends with a `FINDINGS: N` line |
| edit | Full agent loop: reads, writes, shells out under policy |

Switch with `--mode`, `NULLRAY_MODE`, or `/mode`. Print mode defaults
to ask and bumps to edit when `--plan-in` applies a plan.

## Tool gate

`--gate`, `NULLRAY_GATE`, or `/gate` cap which tool kinds run.

| Gate | Allows |
|------|--------|
| 0 | Read-only tools |
| 1 | File writes |
| 2 | Shell commands and MCP calls |
| 3 | Destructive operations |

Aliases: `ask`/read = 0, `edit`/write = 1, `allow`/shell = 2,
`yolo`/full = 3. With no explicit gate, the permission policy implies
one: ask and allow land on 2, yolo on 3. In print mode or without a TTY,
over-gate calls deny instead of asking.

## Permissions

`--perms`, `NULLRAY_PERMS`, or `/perms` control shell confirmation.

- `ask`: prompt before each shell command, `/allow` or `/deny` decide
- `allow`: run without asking
- `yolo`: allow plus gate 3

Edit under `--print` needs `allow` or `yolo`.

## Verify

Post-edit verification is off by default. Enable with
`NULLRAY_VERIFY=1`, `/verify on`, or `--auto` (which sets it). The
verifier resolves in order: the plan's Verify line, AGENTS.md, a
Makefile `make test`, or a detected `go test`, `cargo test`,
`npm test`, `pytest`. A failed verify nudges the agent with parsed
`path:line` findings and can offload the full log to an artifact.
`NULLRAY_VERIFY=<cmd>` forces a custom command.

## Plan contracts

Plan mode writes markdown under `.nullray/plans/` or `--plan-out`. A
complete contract needs Steps, Verify, Success, and Budget sections.
Apply it with `/approve` in the TUI or `--plan-in` headless, which
auto-approves into edit. An empty prompt then becomes "Execute the
approved plan".

## Autonomous mode

`--auto` or `/auto on` sets edit mode, yolo permissions, 80 steps, and
verify. The agent keeps going until done or blocked, and when the work
ends in a pull request it watches CI and addresses feedback rather than
stopping at PR creation.

## Vuln hunts

`--hunt` or `/hunt` turns review mode into a bug hunt. `auto` runs an
explore pass then an oracle pass in print mode. Static profiles:
`balanced`, `explore`, `oracle`, `adversarial`. `NULLRAY_TEMPERATURE`
and `NULLRAY_TOP_P` override the sampling a profile picks.

## Review bot

`nullray --review` reviews a local Git or Fossil diff with no forge.
Scope flags pick the diff: `--staged`, `--unstaged`, `--base REF`,
`--include-untracked`, `--paths a,b`. `--fail-on-findings` exits 1 when
the reply ends `FINDINGS: N` with N > 0, which makes it a CI gate.

## Prompt improvement

`/improve` sends your draft input to the model for a rewrite before the
turn runs. Off by default, opt-in per turn.
