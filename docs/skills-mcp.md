# Skills and MCP

## Skills

Skills are markdown prompt packs that teach the agent a task shape.
A skill is either a flat `.md` file or a directory with `SKILL.md` plus
optional `references/`, `scripts/`, and `assets/`.

### Where they load from

In precedence order:

1. Workspace `.agents/skills/` and `.agents/`
2. Config `~/.config/nullray/skills/`
3. Home `~/.agents/`
4. Packaged `share/nullray/skills/` beside the binary
5. Extra roots via `--skills PATH` or `NULLRAY_SKILLS` (comma-separated)

`--bare` or `NULLRAY_BARE=1` skips home MCP and non-workspace skills.
Explicit `--skills` roots still load under `--bare`.

### Managing

```sh
nullray --list-skills                          # id, description, source
nullray --install-skill ./pack/my-skill        # copies into config skills
nullray --install-skill ./x.md --as review2    # rename on install
nullray --uninstall-skill review2
```

In the TUI, `/skills` lists them and `/skills ID` shows one.

### How they load

The agent gets a catalog of skill ids in the system prompt and pulls a
full body on demand through `list_skills` or `load_skill`, or when the
turn auto-matches one. The cap is 96 loaded skills.

YAML frontmatter may include a `paths` list (globs). When the agent writes
a matching file, that skill body is appended to the tool result. Example:

```yaml
---
name: go
description: Go workspace conventions
paths:
  - "**/*.go"
  - "go.mod"
---
```

## MCP servers

`~/.config/nullray/mcp.json` declares stdio MCP servers to autoload on
startup. Each entry names a command, args, and env. nullray connects,
lists tools, and registers them as `mcp:name` entries on the tool
registry.

### Trust

First-run and drifted tool lists prompt before tools come live, unless:

- `NULLRAY_MCP_ALLOW_ANY=1` autoloads without prompting
- `NULLRAY_MCP_APPROVE_DRIFT=1` re-approves a changed tool list

Servers that batch multiple JSON-RPC frames per write work fine. Hooks
fire on MCP calls the same as built-in tools, and gate level 2 covers
them.

## Hooks

`.nullray/hooks.json` in the workspace defines hooks that run shell
commands around tool calls and session events. Unknown or modified
hooks block until `/hooks trust` approves them. A hook that never
reads stdin cannot stall the turn, because hook stdin feeds through a
helper thread.

Events: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
`PermissionRequest`, `PermissionDenied`, `SubagentStart`,
`SubagentStop`, `Notification`, `SessionStart`, `SessionEnd`, `Stop`,
`PreCommit`. Each command gets `{"event","tool","payload"}` as JSON on
stdin and a 5s timeout. Exit code 2 blocks the action.
`PermissionRequest` may answer the prompt by printing
`{"decision":"allow"}` or `{"decision":"deny","reason":"..."}` to
stdout. `PreToolUse` may rewrite tool args by printing
`{"rewrite":{...}}` (args replaced wholesale). Hook children run with
system dirs first on PATH so sandboxed exec resolves predictably.

## Script tools

Executable files in `~/.config/nullray/tools/` (user level, always
trusted) and `.nullray/tools/` (workspace level, needs hooks trust or
`NULLRAY_SCRIPT_TOOLS=1`) become agent tools named after the file.
Extensions `.sh`, `.bash`, `.py`, `.js` pick the interpreter; any
executable without an extension runs directly. Tool args arrive as
JSON on stdin and in `NULLRAY_TOOL_ARGS`; stdout becomes the tool
result. Optional sidecars: `<name>.md` (description),
`<name>.schema.json` (args schema), `<name>.meta` (`read`, `write`,
or `shell` gating kind, default `shell`).

## Scheduling

The `schedule_prompt` tool and `/loop`, `/remind` commands inject a
prompt into the session later (`in 10m`, `every 1h`, or a 5-field
cron). Minimum interval is 60s, the cap is 50 jobs, recurring jobs
expire after 7 days, and 3 consecutive failures pause a job. Durable
jobs survive restarts via `.nullray/scheduled_tasks.json`.
`NULLRAY_HEARTBEAT=<interval>` runs a periodic beat that reads
`.nullray/HEARTBEAT.md` when it exists. `NULLRAY_SCHEDULE=0` disables
scheduling.

## External harnesses

The `harness_run` tool delegates a task to another agent CLI installed on
the machine, and `harness_list` shows which are detected. Built-in presets
cover claude, opencode, gemini, codex, aider, goose, crush, and pi. Add or
override engines in `~/.config/nullray/harnesses.json` or
`.nullray/harnesses.json` (workspace file needs hooks trust):

```json
{"echobot": {"bin": "opencode", "argv": ["run", "{prompt}"], "timeout_sec": 300, "output": "text"}}
```

`{prompt}` is passed as a single argv element, never through a shell.
Runs execute under the sandbox with the workspace as cwd, so binaries
outside the granted dirs need `NULLRAY_SANDBOX_EXTRA_RO` to exec. Output
is capped head+tail and withheld when it looks secret.
`NULLRAY_HARNESS=0` disables the tools.

## Model profiles

`~/.config/nullray/model_profiles.json` and
`.nullray/model_profiles.json` tune request settings per model glob, first
match wins:

```json
{"profiles": [{"match": "qwen*", "num_ctx": 32768, "temperature": 0.6,
               "reasoning": "off", "one_tool_per_turn": true,
               "prompt_tier": "lean", "parallel_tool_calls": false}]}
```

Fields: `num_ctx` (Ollama window, NULLRAY_OLLAMA_NUM_CTX still wins),
`temperature`, `top_p`, `reasoning` (off|on), `prompt_tier`
(tiny|lean|full), `parallel_tool_calls` (false emits
parallel_tool_calls:false on OpenAI-compatible requests).

For weak tool-call models: `NULLRAY_TOOL_RETRY` (default 2) bounds the
per-turn malformed-call retries, and `NULLRAY_TOOLSHIM=<model>` (or `1`
for the active model) runs a small interpreter pass that converts
intended-but-unstructured tool text into real calls, capped at 1 attempt
per step and 2 per turn. `NULLRAY_SCHEMA_CLEAN=1|0` overrides the schema
sanitizer that strips grammar-heavy keywords ($defs, pattern, format and
friends) on llamacpp and ollama. `NULLRAY_MODEL_SMOKE=1|auto` probes each
model once with a canned tool call and shows the verdict in /providers.

## Session tasks

`todo_write`, `todo_update`, `todo_add`, and `todo_list` manage a
per-session task list persisted to `.nullray/todos/`. Open items are
injected into every request as an `<open_tasks>` block, and a stale
warning appears after 2 turns with no task update, so the model is
nudged to keep the list current instead of forgetting it. `/todo`
shows the list. `NULLRAY_TODO=0` disables.
