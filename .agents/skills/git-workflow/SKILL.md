---
name: git-workflow
description: >
  Use local vcs_* tools for status, diff, log, commit, branch, merge, and
  rebase. Enable network and force-push gates before remote or PR work.
---

# Git workflow

Prefer built-in VCS tools over raw git shell for local repository work.

## Local tools

Always available without network env:

| Tool | Use |
|------|-----|
| `vcs_status` | Working tree summary |
| `vcs_diff` | Staged and unstaged changes |
| `vcs_log` | Recent history |
| `vcs_commit` | Local commit without push |
| `vcs_branch` | List, create, or switch branches |
| `vcs_merge` | Merge a local branch |
| `vcs_rebase` | Rebase (Git only) |

These tools refuse dirty-tree merges and rebases unless `allow_dirty` is set.

## Network

Push, pull, fetch, and PR tools stay off until `NULLRAY_VCS_NETWORK=1`. Set it only when the user wants remote interaction.

Force-push to `main` or `master` needs `NULLRAY_VCS_FORCE=1` in addition to network access.

## Pull requests

Use `vcs_pr_*` tools for GitHub PR work. They wrap `gh` with the same network gate. Do not run raw `gh pr create` through shell when the VCS PR tools cover the task.

Local commit hooks can still run on `vcs_commit` via `PreCommit` in hooks.json.
