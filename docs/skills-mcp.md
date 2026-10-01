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

`.nullray/hooks.json` in the workspace defines `PreToolUse` and session
lifecycle hooks that run shell commands around tool calls. Unknown or
modified hooks block until `/hooks trust` approves them. A hook that
never reads stdin cannot stall the turn, because hook stdin feeds
through a helper thread.
