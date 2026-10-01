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
| `/delete NAME` | Delete a saved session from disk |
| `/ephemeral on\|off` | Toggle transcript persistence |
| `/group NAME\|none` | Join a shared context group |
| `/tab ...` | list, new, open, next, prev, close, N |

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
| `/review on\|off\|local [scope]` | Review pass or local VCS review |
| `/tools` | Toggle agent tools |
| `/approve` | Approve a plan contract and switch to edit |

## Provider and model

| Command | Action |
|---------|--------|
| `/provider [ID\|next\|prev\|setup]` | Show or switch provider |
| `/providers` | List providers and readiness |
| `/model [NAME\|lock\|unlock]` | Show or set the model |
| `/models [policy]` | Live catalog, or policy view |
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
| `/close` | Close the view pane |
| `/undo` | Undo the last agent file write |
| `/checkpoint [list\|restore N\|diff N]` | File checkpoints |
| `/drop N` | Drop the last N user turns (backup saved) |
| `/compact` | Compact conversation history |
| `/expand` | Expand or collapse all tool and think blocks |

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
| `/status` | Mode, plan, verify, tokens, context |
| `/copy` | Copy selection or last reply |
| `/reset` | Wipe sessions and config (needs confirm) |
| `/help` or `/?` | Command list |
