---
name: hooks
description: >
  Block or gate tool runs with PreToolUse hooks in hooks.json. Global config
  or workspace .nullray/hooks.json, exit code 2 blocks the tool.
---

# Hooks

Hooks run bounded subprocesses around agent events. `PreToolUse` fires before each tool call. Exit code 2 blocks the tool and returns a message to the agent.

Config paths:

- Global: `~/.config/nullray/hooks.json`
- Workspace: `.nullray/hooks.json`

Disable all hooks with `NULLRAY_HOOKS=0`.

## Input

Each hook receives JSON on stdin:

```json
{"event":"PreToolUse","tool":"vcs_push","payload":"{...}"}
```

`payload` is the tool arguments JSON string.

## Block vcs_push

Refuse every push until the user removes the hook or approves network access separately:

```json
{
  "PreToolUse": [
    "python3 -c \"import sys,json; d=json.load(sys.stdin); sys.exit(2 if d.get('tool')=='vcs_push' else 0)\""
  ]
}
```

## Block fetch_url domains

Reject URLs whose host ends with a blocked suffix:

```json
{
  "PreToolUse": [
    "python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); p=json.loads(d.get('payload') or '{}'); u=p.get('url',''); h=urllib.parse.urlparse(u).hostname or ''; blocked=('evil.example','pastebin.com'); sys.exit(2 if d.get('tool')=='fetch_url' and any(h==b or h.endswith('.'+b) for b in blocked) else 0)\""
  ]
}
```

Adjust the `blocked` tuple to match policy. Keep hook commands short and fast. Default timeout is five seconds (`NULLRAY_HOOK_TIMEOUT_MS`).
