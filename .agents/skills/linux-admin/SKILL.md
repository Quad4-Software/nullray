---
name: linux-admin
description: >
  Install packages, manage systemd units, and edit system config under /etc
  with elevated commands while respecting sandbox ops profiles and shell policy.
---

# Linux administration

Use this skill for host packages, systemd, and system-wide configuration outside the workspace.

## Ops and paths

Set `NULLRAY_OPS=desktop` when the task needs read-write access to `$XDG_CONFIG_HOME` or `~/.config`. Desktop config can rewrite shell and compositor autostart. Treat it as code execution.

Workspace files stay under the sandbox workspace grant. User config lives under `~/.config` and needs the desktop ops profile or an explicit absolute path in `NULLRAY_SANDBOX_EXTRA_RW`.

System files under `/etc` are outside normal grants. Use elevated commands through the nullray elevate broker (`sudo`, `doas`, or `pkexec`). Passwords stay on the TUI askpass path and never enter tool results.

## Packages

Match the host package manager. Use `pacman` on Arch-based systems and `apt` on Debian-based systems. Prefer read-only queries (`-Q`, `list`, `search`) before install or remove.

Install and remove need shell access. Prefix allowed commands in `NULLRAY_SHELL_ALLOW` when `NULLRAY_PERMS=allow`. Example: `pacman -S`, `apt install`.

## Systemd

Prefer user units (`systemctl --user`) when the service should run as the login user. Use `scaffold` with `systemd-user.service` as a starting template.

System units under `/etc/systemd/system` need elevation. After editing, run `systemctl daemon-reload` and restart the unit. Check status with `systemctl status` before claiming the service is healthy.

## Shell policy

Built-in deny patterns still block destructive commands (`rm -rf /`, `mkfs`, `dd if=`, mass chmod on `/`, and similar). Extra patterns can go in `NULLRAY_SHELL_DENY`.

Do not bypass the denylist. Do not pipe remote scripts into a shell.
