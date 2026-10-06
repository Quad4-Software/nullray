---
name: electron
description: >
  Electron 44+ desktop security: contextIsolation, sandbox, ASAR integrity
  fuses, shell.openExternal allowlists, and IPC sender checks. Use when
  building or reviewing Electron apps, packaging asar, or hardening shell.
---

# Electron 44+

Load this skill for Electron apps. Current line verified on npm includes
44.3.0. Always prefer a current patched Electron.

## Hard requirements

| Control | Default posture |
|---------|-----------------|
| `contextIsolation` | On in every renderer |
| `nodeIntegration` | Off for any remote/untrusted content |
| `sandbox` | On for renderers |
| `webSecurity` | Do not disable |
| CSP | Restrictive (`script-src 'self'` ...) |
| IPC | Validate `event.sender` / frame |
| Navigation / new windows | Deny by default, allowlist |

## shell.openExternal

Never pass untrusted strings. Parse `URL`, allowlist protocols (`https:`,
maybe `mailto:`), deny `file:` and custom handlers unless intentional.

Also install `setPermissionRequestHandler` that denies `openExternal` for
untrusted content (sandboxed iframe footgun fixed in earlier lines, still
defend in depth).

## ASAR integrity

Supported on macOS (Electron 16+) and Windows (Electron 30+), not Linux.
Enable fuses together:

1. `EnableEmbeddedAsarIntegrityValidation`
2. `OnlyLoadAppFromAsar`

Requires `@electron/asar` packaging and platform metadata (Info.plist /
Windows Integrity resource). Forge/Packager can auto-wire when asar is on
(min versions documented upstream). Integrity is **off by default**.

Detail: [references/asar-shell.md](references/asar-shell.md).
URLs: [references/urls.md](references/urls.md).

## Agent checklist

1. Read Electron security tutorial before changing `webPreferences`
2. Grep for `openExternal`, `nodeIntegration`, `contextIsolation: false`
3. Confirm fuse settings in the packager config
4. Pin Electron and audit CVEs after bumps
