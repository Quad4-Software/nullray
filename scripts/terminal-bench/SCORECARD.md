# Terminal-Bench scorecard

Fill after a reproducible run. Do not commit API keys.

| Field | Value |
|-------|-------|
| git SHA | |
| date (UTC) | |
| dataset | terminal-bench-core (pin version) |
| task set | |
| chat model | |
| embed model | |
| NULLRAY_RAG | 0 or 1 |
| adapter | scripts/terminal-bench/nullray_agent.py |
| resolved / total | |
| tokens (if known) | |
| notes | |

## How to run

See README.md in this directory. Copy nullray_agent.py into the temp adapter path or set PYTHONPATH to this folder.

Always use a /tmp workspace root for the harness. Never point --workspace at the nullray source tree.
