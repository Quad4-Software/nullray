# Quick start

## First run

```sh
nullray
```

On startup nullray scans for config from other AI CLIs already on the
machine (Claude Code, OpenCode, pi, Codex, Gemini CLI, Qwen Code, Crush,
goose, aider, aichat, llm) and adopts API keys, base URLs, and a
provider/model pick into unset variables. To see what was found:

```sh
nullray --doctor
```

Look for the `foreign config` section. If nothing was detected or
adopted, the TUI opens a setup overlay that asks for a provider and key.
Reopen it any time with `/setup`. Keys save to
`~/.config/nullray/env`.

Prefer to configure by hand? Either export variables or write them to
the env file:

```ini
NULLRAY_PROVIDER=openrouter
NULLRAY_MODEL=google/gemini-3.8-flash
OPENROUTER_API_KEY=sk-or-...
```

Local inference needs no key at all:

```sh
nullray --provider ollama --model gemma3:4b
```

## Talking to it

Type a question at the prompt and press Enter. The reply streams into
the transcript. While the agent works, the status line shows elapsed
seconds and the live tool.

A few commands cover most daily use:

| Command | What it does |
|---------|--------------|
| `/mode ask\|plan\|review\|edit` | Switch what the agent is allowed to do |
| `/provider` | Show or switch providers |
| `/model NAME` | Switch models mid-session |
| `/sessions` | List and resume saved sessions |
| `/status` | Mode, plan state, verify, tokens, context size |
| `/help` | Everything else |

Ask mode is read-only. Edit mode lets the agent write files and run
shell commands under the permission policy (`/perms`) and the tool gate
(`/gate`). Plan mode produces a written Done Contract you approve with
`/approve` before any edits happen.

## Headless use

```sh
nullray -q "what does session_init do?"
nullray --print --mode edit --perms allow "add a --count flag"
git diff | nullray --print --mode review "review this diff"
```

Print mode is ephemeral by default, reads piped stdin when not a TTY,
and exits when the reply lands. See [CLI reference](cli.md).

## Sessions

Sessions persist automatically under `~/.config/nullray/sessions`.
Give one a name with `/name work`, resume it later with
`nullray --session work` or `/resume work`. `-e` or `/ephemeral on`
runs without saving.

## Where to next

- [Providers](providers.md) for keys, model picks, and local servers
- [Modes and permissions](modes.md) for the safety model
- [Sandbox](sandbox.md) for what tool commands can and cannot reach
