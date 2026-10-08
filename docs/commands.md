# Slash commands

Every command the TUI input accepts, grouped by area. `/help` prints
this list in-app.

## Sessions and tabs

| Command | Action |
|---------|--------|
| `/sessions` | List saved sessions |
| `/search QUERY` | Search session names and transcript text |
| `/resume NAME` | Open a saved session |
| `/name NAME [--force]` | Rename the current session |
| `/new [NAME]` | New session in a new tab |
| `/fork NAME [--force]` | Copy the session under a new name |
| `/delete [NAME\|tab\|current]` | Delete a session (bare = current) |
| `/rm ...` | Alias for `/delete` |
| `/close [tab\|view\|NAME\|N]` | Close view, current tab, or named tab |
| `/ephemeral on\|off` | Toggle transcript persistence |
| `/group NAME\|none` | Join a shared context group |
| `/tab ...` | list, new, open, next, prev, close [NAME\|N], N |

## Agent control

| Command | Action |
|---------|--------|
| `/mode ask\|plan\|review\|edit` | Switch mode |
| `/gate 0..3` | Tool capability gate |
| `/perms ask\|allow\|yolo` | Shell permission policy |
| `/verify on\|off\|CMD` | Post-edit verify gate |
| `/auto on\|off` | Autonomous mode |
| `/hunt [off\|auto\|balanced\|explore\|oracle\|adversarial]` | Vuln hunt profile |
| `/improve` | Rewrite the draft prompt via the model |
| `/pause` | Pause after the current step |
| `/stop` or `/cancel` | Abort the running turn |
| `/continue [note]` | Resume after pause or stop |
| `/retry` | Retry the last user turn |
| `/rewind [N]` | Restore files, drop last N user turns, summarize from here |
| `/review on\|off\|local [scope]` | Review pass or local VCS review |
| `/tools` | Toggle agent tools |
| `/approve` | Approve a plan contract and switch to edit |

## Provider and model

| Command | Action |
|---------|--------|
| `/provider [ID\|next\|prev\|setup]` | Show or switch provider |
| `/providers` | List providers and readiness |
| `/model [NAME\|lock\|unlock]` | Show or set the model (type `/model ` for catalog suggestions) |
| `/models [policy]` | Live catalog (models.dev cache fallback), or policy view |
| `/reasoning LEVEL` | Reasoning effort (alias `/think`) |
| `/temp [0-2\|off]` | Temperature override |
| `/top_p [0-1\|off]` | top_p override |
| `/quirks` | Active model output workarounds |
| `/setup` | Setup wizard |
| `/usage [json\|export PATH]` | Token and cost summary |
| `/hide on\|off` | Hide balances and credit labels |

## Files and view

| Command | Action |
|---------|--------|
| `/attach PATH` | Queue text or media for the next message |
| `/view [PATH\|auto on\|off]` | Open a file in the side pane |
| `/artifact ID` | Open an LID artifact in the pane |
| `/close [tab\|view\|NAME\|N]` | Close view pane or a tab |
| `/undo` | Undo the last agent file write |
| `/checkpoint [list\|restore N\|diff N]` | File checkpoints |
| `/drop N` | Drop the last N user turns (backup saved) |
| `/compact` | Compact conversation history |
| `/expand` | Expand or collapse all tool and think blocks |
| `/history` | Scrollable full session history including thinking |

## Sandbox and ops

| Command | Action |
|---------|--------|
| `/ops` | Show NULLRAY_OPS grants and extras |
| `/secrets PATH` | Allow reading a secret path |
| `/hooks trust` | Re-approve workspace hooks.json |
| `/allow` | Approve a pending shell command |
| `/deny` | Drop a pending shell command |

## Miscellaneous

| Command | Action |
|---------|--------|
| `/theme NAME` | Switch theme, `/themes` lists them |
| `/keys` | Show key bindings |
| `/skills [ID]` | List skills or show one |
| `/agents [...]` | Subagent roster and controls |
| `/todo` | Show the session task list |
| `/loop <every> <prompt>` | Recurring prompt in this session |
| `/remind <in> <text>` | One-shot reminder prompt |
| `/schedule [list\|cancel]` | Manage scheduled prompts |
| `/watch [list\|add\|show\|rm]` | Standing watches that digest and notify only on new hits |
| `/status` | Mode, plan, verify, tokens, agent step budget |
| `/steps [N\|auto\|default]` | Max tool steps per turn (default 24, auto 80) |
| `/context` | Per-category context size (system, tools, messages, memory) |
| `/copy` | Copy selection or last reply |
| `/reset` | Wipe sessions and config (needs confirm) |
| `/tui [get\|reset\|lock\|unlock\|on\|off\|THEME]` | Malleable TUI theme controls |
| `/encrypt [on KEY\|off\|status]` | Seal session transcripts at rest |
| `/scrub [all\|last\|matching NEEDLE]` | Redact or forget session content |
| `/secret list\|set\|ask\|forget\|has\|clear\|backend` | Agent vault secrets (names only, optional keyring) |
| `/key` `/token` | Aliases for `/secret` |
| `/demo malleable` | Smoke show_view password vault + privacy UI |
| `/canvas list\|open\|save\|rm` | Persist and reopen agent panel UIs |
| `/art figlet\|demo\|show JSON` | Programmatic ASCII/ANSI art (engine, not freehand) |
| `/learn ID [description]` | Save a compact skill from the last assistant reply |
| `/agents worktree [--force]` | Prune orphan edit-subagent worktrees |
| `/help` or `/?` | Command list |

Agent tools for interactive UI (not slash commands): `ask_question`,
`ask_secret`, `show_view` (sized/colored multi-field forms, panel or modal),
and `set_tui` (session or global theme). Gate with `NULLRAY_UI_MALLEABLE=0`.

## Custom commands

Markdown files in `.nullray/commands/` (and config `commands/`) become
slash commands named after the file. `$ARGUMENTS` and `$1` through `$9` expand.
Frontmatter `name` and `description` are optional. `NULLRAY_COMMANDS=0`
turns this off.
