---
name: odin-idioms
description: >
  Odin package layout, build tags, ownership, and error style for nullray.
  Use when adding or editing .odin files under nullray/ or cmd/.
---

# Odin idioms

## Packages

One package name per directory under nullray/. Import with the collection:

```
import "nullray:provider"
```

package declaration matches the folder.

## Platform files

Split OS-specific code into #+build tagged files. Do not put platform imports behind when ODIN_OS in a shared file that every OS compiles.

| Example | Tag |
|---------|-----|
| sandbox/landlock_linux.odin | linux |
| sandbox/seccomp_linux.odin | linux |
| sandbox/sandbox_stub.odin | !linux |
| ui/term_linux.odin | linux |
| ui/term_bsd.odin | darwin, freebsd, netbsd, openbsd |
| ui/term_windows.odin | windows |
| *_unix.odin / *_windows.odin | process and keys |

when ODIN_OS == .Linux is fine for runtime branches inside already-compiled shared code (sandbox/sandbox.odin). Prefer file tags for imports and APIs missing on other targets.

## Slices and ownership

Never return a slice into a stack buffer or local array. Caller owns heap data or supplies the allocator.

[dynamic]T: make, append, delete (destroy nested owned fields first).

Strings on structs: strings.clone on write, delete on destroy. Env lookups via temp_allocator are not owned. Clone before storing past the current scope.

Temp: short paths, lowercasing, JSON scratch. Permanent: session, provider, tool state plus an explicit destroy path.

## Switches and errors

#partial switch when not every case is handled on purpose. Document surprising omissions.

Errors are usually (value, err: string) or a field err: string. Clone error text with the caller allocator when it must outlive temp. Empty string means success when that is the local convention (check the call site).
