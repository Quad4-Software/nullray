# Terminal-Bench adapter

Point a Terminal-Bench agent adapter at nullray print mode. Build nullray first, then have the adapter pass each task prompt to:

```text
bin/nullray --print --mode edit --perms yolo --bare --workspace "$PWD" "$TASK_PROMPT"
```

Use `--mode ask` for read-only benchmark tasks. Keep each benchmark workspace isolated because edit mode can change files and run shell commands inside the configured workspace.

Provider credentials come from the process environment or `~/.config/nullray/env`. Capture stdout as the agent answer and treat exit code 2 as a provider or runtime failure.
