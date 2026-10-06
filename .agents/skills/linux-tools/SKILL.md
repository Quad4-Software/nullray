---
name: linux-tools
description: >
  Common Linux CLI usage for agents: find/fd, grep/rg, jq, curl, ss/ip,
  systemctl, journalctl, tar, permissions, and safe ops habits. Use when
  diagnosing hosts, writing shell steps, or choosing the right tool.
---

# Linux tools

Load this skill before non-trivial shell diagnosis. Prefer
[unix-docs](../unix-docs/SKILL.md) (`read_man`, `apropos`, `read_tldr`) when a
flag is uncertain.

## Choose the tool

| Need | Prefer | Notes |
|------|--------|-------|
| Fast content search | `rg` | Falls back to `grep -R` if missing |
| Filename search | `fd` or `find` | `find` is ubiquitous |
| JSON | `jq` | Validate before complex filters |
| HTTP | `curl -fsSL` | Fail on HTTP errors with `-f` when appropriate |
| Ports / sockets | `ss -lntp` | Prefer over aging `netstat` |
| Addresses / routes | `ip` | `ip addr`, `ip route` |
| DNS | `dig` / `resolvectl` | |
| Services | `systemctl status/start` | User units: `--user` |
| Logs | `journalctl -u NAME -e` | Cap with `-n` / time ranges |
| Disk | `df -h`, `du -sh` | |
| Archives | `tar`, `gzip` | Never extract untrusted tar as root blindly |
| Processes | `ps`, `pidof`, `top` | |

Recipes: [references/recipes.md](references/recipes.md).
URLs: [references/urls.md](references/urls.md).

## Safety habits

1. Quote variables. Prefer `"$var"`
2. Dry-run destructive globs. List before `rm`
3. Avoid `chmod -R 777`
4. Prefer absolute paths in scripts
5. Cap output (`head`, `rg --max-count`) in agent contexts
6. Use sudo only when required. See elevate / sandbox skills in nullray

## nullray notes

Sandbox may block paths or syscalls. Prefer docs tools and scoped reads over
broad filesystem walks when confined.
