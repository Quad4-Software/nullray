---
name: agent-footguns
description: >
  Common coding-agent mistakes: invented APIs, skipped verify, secret leaks,
  destructive git, half refactors, wrong files, and unsafe shell. Use before
  large edits, reviews of agent output, or when an agent loop looks stuck.
---

# Agent footguns

Load this skill when reviewing agent behavior or starting risky autonomous
work. Pair with [prose](../prose/SKILL.md) and [attack-surface](../attack-surface/SKILL.md).

## High-frequency failures

| Mistake | Do instead |
|---------|------------|
| Invent APIs / flags from memory | Read code, man pages, or official URLs |
| Edit unrelated files | Diff scope to the task |
| Skip tests after edits | Run project verify (`make test` here) |
| Commit secrets or paste keys into repo | Env vars only. Rotate if exposed |
| Destructive git (`reset --hard`, force push) | Only with explicit user request |
| Claim tests passed without running | Show command output |
| Rewrite architecture unasked | Match existing patterns |
| Leave half-migrated renames | Finish or revert |
| Unbounded `find` / `rm` / `chmod -R` | Cap, quote, dry-run |
| Trust model version trivia | Check npm/docs timestamps |

Checklist: [references/checklist.md](references/checklist.md).
URLs: [references/urls.md](references/urls.md).

## Context and honesty

1. Prefer `load_skill` / `list_skills` over guessing stack advice
2. Cite paths and commands you actually used
3. If blocked by sandbox or missing tools, say so
4. Do not silently widen scope into drive-by cleanups

## Code generation risks

- Path joins without root confinement (TOCTOU / traversal)
- Shell string concat instead of argv arrays
- Logging secrets into tool results
- Disabling TLS verify "temporarily"
- Catch-all exception handlers that hide failures

## Recovery

When an agent digs a hole: stop, re-read the user ask, restore from git or
backups, re-run verify, then continue with a smaller step list.
