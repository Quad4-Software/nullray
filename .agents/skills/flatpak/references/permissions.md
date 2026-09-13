# Flatpak permissions

## finish-args patterns

| Arg | Meaning |
|-----|---------|
| `--share=network` | Network access |
| `--share=ipc` | IPC (often with display) |
| `--socket=wayland` / `fallback-x11` | Display |
| `--device=dri` | GPU |
| `--filesystem=home` | Full home (broad) |
| `--filesystem=xdg-download` | Downloads only |
| `--talk-name=...` | Named session bus service |

## Portals

Use toolkit-native choosers and URI openers so xdg-desktop-portal mediates
access without permanent broad FS rights.

Docs: https://docs.flatpak.org/en/latest/portals.html

## Overrides

Users can widen access with Flatseal / `flatpak override`. Do not rely on
overrides as the default design.
