---
name: odin-idioms
description: >
  Odin package layout, build tags, ownership, and error style for nullray.
  Use when adding or editing .odin files under nullray/ or cmd/.
---

# Odin idioms (nullray)

## Packages

One package name per directory under `nullray/`. Import with the collection: `import "nullray:provider"`. Keep `package` declarations matching the folder.

## Platform files

Split OS-specific code into separate files with `#+build` tags. Do not put platform imports behind `when ODIN_OS` in a shared file that other platforms compile.

Examples in this tree:

- `sandbox/landlock_linux.odin`, `sandbox/seccomp_linux.odin`
- `sandbox/sandbox_stub.odin` with `#+build !linux`
- `ui/term_linux.odin`, `ui/term_bsd.odin`, `ui/term_windows.odin`
- `*_unix.odin` / `*_windows.odin` for process and keys

Use `when ODIN_OS == .Linux` (and similar) only for runtime branches inside already-compiled code, as in `sandbox/sandbox.odin`. Prefer file tags for imports and APIs that do not exist on other OS targets.

## Slices and ownership

Never return a slice into a stack buffer or a local array. The caller must own heap data or use an allocator the caller controls.

`[dynamic]T` is owned by the holder. `make` it, `append` into it, `delete` it (and destroy nested owned fields first).

Strings stored on structs: `strings.clone` on write, `delete` on destroy. Env lookups that use `context.temp_allocator` are not owned. Clone before storing past the current scope.

Short-lived paths, lowercasing, and JSON scratch: prefer `context.temp_allocator`. Permanent session, provider, and tool state: default allocator plus an explicit destroy path.

## Switches and errors

Use `#partial switch` when not every enum or union case is handled on purpose. Document why if the omission is surprising.

Errors are usually `(value, err: string)` or a struct field like `err: string`. Clone error text with the caller's allocator when the string must outlive temp. Empty string means success when that is the local convention (check the call site).
