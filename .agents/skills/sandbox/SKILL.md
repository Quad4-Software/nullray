---
name: sandbox
description: >
  Configure and diagnose nullray sandbox modes, filesystem policy, Linux
  Landlock and seccomp, Windows isolation, privacy controls, and doctor output.
---

# Sandbox

Use this skill when changing sandbox policy or explaining isolation claims.

## Modes

| Value | Behavior |
|-------|----------|
| `off` | Applies no OS sandbox |
| `soft` or `warn` | Tries supported controls and continues with a warning when a control is unavailable |
| `strict` or `on` | Fails startup when a requested control cannot be applied |

Soft and warn select the same mode. The default is warn. Configure it with `NULLRAY_SANDBOX`.

`NULLRAY_SANDBOX_FS=rw|ro` controls workspace writes. `NULLRAY_SANDBOX_NET=full|local|off` records network policy. Check the backend before claiming network enforcement.

## Platform backends

Linux applies Landlock path rules and an amd64 seccomp deny list. Landlock grants the workspace, config directory, runtime directory, and selected system paths. It also sets `NO_NEW_PRIVS`.

Windows has a Job Object spawn-helper stub. AppContainer confinement is not implemented. Strict mode fails while the helper is unavailable.

macOS has no OS sandbox backend. Warn mode continues without confinement. Strict mode fails.

Read the full matrix in [../../references/sandbox.md](../../references/sandbox.md) and the claim limits in [../../references/caveats.md](../../references/caveats.md).

## Diagnosis

Run `nullray --doctor` to print configured mode, applied state, Landlock ABI, seccomp support, config paths, and relevant environment values.

The source man page is `man/nullray.1`. Installed packages place it under the prefix at `share/man/man1/nullray.1`. `nullray --man` prints the bundled source.

The `read_man` and `apropos` agent tools query host manuals on Linux. They do not bypass sandbox path or mode policy.
