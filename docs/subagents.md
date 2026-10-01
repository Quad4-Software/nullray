# Subagents

The `task` tool spawns child agents for scoped work. Subagents keep the
parent turn small: a child explores, plans, or edits in isolation and
returns a short result.

## Types

| `subagent_type` | Returns | Isolation |
|-----------------|---------|-----------|
| `locate` | `path:start-end` file spans | shared, read-only |
| `architect` | A Done Contract plan | shared, ask mode |
| `explore` | A summary of the code | shared, path leases |
| `edit` | Applied changes after verify | worktree under `.nullray/worktrees/` |
| `review` | Findings | shared |
| `verify` | Test/check result | shared |

`locate` and `architect` have hard step budgets
(`NULLRAY_LOCATE_STEPS` default 4, `NULLRAY_ARCHITECT_STEPS` default 6)
so they cannot wander. `locate` only gets read tools
(`repo_map`, `glob_files`, `grep_files`, `read_file`, `list_dir`) and
returns citable spans rather than full files. `architect` adds
`list_scaffolds` and produces a plan the parent can apply.

## Caps and control

- `NULLRAY_SUBAGENTS` caps concurrent children (default 3). `0`,
  `/agents off`, or `--no-subagents` disables the tool.
- `NULLRAY_SUBAGENT_DEPTH` caps nesting (default 1).
- Parent tools: `agents_status`, `agents_peek`, `agents_progress`,
  `agents_wait`, `agents_verify`, plus `knowledge_*`, `model_use`,
  `board_*`, `send_message`, and `read_messages`.
- `/agents` in the TUI shows the roster and applies completed edit
  work. `agents_verify` should run before `/agents apply`.
- `NULLRAY_SUBAGENT_TEAMS=1` enables peer messaging between children.

## Model roles

`~/.config/nullray/models.json` and `.nullray/models.json` map roles
(explore, edit, review, verify) to specific models. A common setup maps
explore and architect work to a fast local model and edit/verify to a
stronger one. `/model lock` freezes the current model so role switches
cannot change it.

## Isolation

Shared isolation gives children the same workspace with path leases so
two children do not collide on the same file. Edit children instead get
a git worktree under `.nullray/worktrees/`, work alone, and their diff
applies only after verify and apply.
