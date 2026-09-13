---
name: wails
description: >
  Wails v3 (beta) Go desktop apps: services, static binding generation,
  Taskfile builds, events, and v2 migration. Use when building or porting
  Wails apps with a Go backend and web frontend.
---

# Wails v3

Load this skill for Wails v3. Desktop API is treated as stable by upstream while
the overall release remains beta. v2 stays the marked stable line. Test before
production.

## Mental model

| v2 idea | v3 |
|---------|-----|
| Context-bound bindings | Standalone Go **services** registered on the app |
| Opaque `wails build` | Visible Taskfile + `wails3` tool commands |
| Runtime package helpers | Explicit app / window APIs |
| Reflection-ish discovery | Static analysis binding generation |

CLI: `go install github.com/wailsapp/wails/v3/cmd/wails3@latest`

Common commands: `wails3 dev`, `wails3 build`, `wails3 generate bindings`.

## Services and bindings

1. Write ordinary Go structs with exported methods
2. Register as services in application options
3. Run `wails3 generate bindings` (add `-ts` for TypeScript)
4. Import generated files under `frontend/bindings/...`

Do not hand-edit generated bindings. Prefer events for progress/streaming.

Detail: [references/services.md](references/services.md).
URLs: [references/urls.md](references/urls.md).

## Migration

Port lifecycle, replace runtime package calls, regenerate bindings, retest
multi-window / systray / dialogs. See upstream v2-to-v3 guide.
