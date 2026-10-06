---
name: flatpak
description: >
  Flatpak manifests, finish-args least privilege, portals, and packaging for
  Linux apps including nullray. Use when editing Flatpak YAML, reviewing sandbox
  permissions, or shipping to Flathub.
---

# Flatpak

Load this skill for Flatpak packaging. Prefer portals over broad host access.

## Manifest basics

| Field | Role |
|-------|------|
| `app-id` | Reverse-DNS id (nullray: `xyz.nullray.code`) |
| `runtime` / `sdk` | Shared platform (e.g. Freedesktop 25.08) |
| `command` | Binary inside `/app` |
| `finish-args` | Sandbox grants applied at finish |
| `modules` | Build steps and sources |

nullray tree: `packaging/flatpak/xyz.nullray.code.yml`.

## Permission posture

Grant the minimum. Prefer:

- Portals for files, URIs, screenshots, notifications
- Narrow filesystem (`xdg-config/...:create`, specific dirs) over `filesystem=home`
- Avoid `socket=system-bus` and `filesystem=host` unless justified

Detail: [references/permissions.md](references/permissions.md).
URLs: [references/urls.md](references/urls.md).

## Agent checklist

1. Diff `finish-args` against the feature that needs each grant
2. Document why network / home / IPC is required
3. Keep desktop + metainfo + icon in sync with app-id
4. Test with `flatpak-builder` / CI packaging scripts in this repo

## Related

[sandbox](../sandbox/SKILL.md), [landlock-seccomp](../landlock-seccomp/SKILL.md),
[supply-chain](../supply-chain/SKILL.md).
