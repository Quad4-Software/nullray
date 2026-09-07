# Footguns

Mistakes that burn time in this tree. Pair with memory and tui skills.

## Never

| Mistake | Why |
|---------|-----|
| Keep temp_allocator pointers across frames, jobs, HTTP, or threads | loop_run free_all each iteration |
| Write ANSI into Buffer cells | present owns escapes |
| Skip CELL_WIDE_CONT after wide runes | corrupt diff and cursor |
| Use len(s) as display columns | use rune_cols / string_cols |
| Merge plat backends into one untagged file | #+build files only |
| Expect splash keys to queue | input dropped while splash_active |
| Rely on binds_resolve for Esc-stop | busy cancel hardcoded, stop_agent unused |
| Double-free nested owned strings | delete once, clone on replace |
| Skip destroy pairs | app_destroy, loop_close, buffer_destroy, registry_destroy, session_destroy |
| ODIN_TEST_THREADS != 1 with shared globals | Makefile sets =1 |
| Strict sandbox on non-Linux | fails with sandbox requires linux |

## Ownership

Creator owns heap strings and [dynamic]T until a documented handoff.

```
replace field: delete(old) then strings.clone(new)
job Provider copy: provider_destroy in defer
clipboard_paste: caller delete
session_set_status: clones, temp arg OK
```

Temp: env lookup, path join, JSON parse, frame draw helpers, builders that feed a final clone.

Permanent: App, Session, Provider, tool/MCP registries.

## Sandbox

Modes: Off / Warn (default) / Strict via NULLRAY_SANDBOX.

| OS | Warn | Strict |
|----|------|--------|
| Linux | landlock/seccomp fail continues with warn | fail Result.ok=false |
| other | skip | fail sandbox requires linux |

Stub: sandbox_stub.odin #+build !linux. apply uses when ODIN_OS == .Linux for runtime branch.

## Session / tools / agent

- Messages: clone content, destroy_message / session_destroy
- Pending events: clone text/name/reasoning, delete on consume/destroy
- Tool (out, err): empty err means success, clone to caller allocator
- Args JSON on temp, clone extracted strings out
- Perms: NULLRAY_PERMS ask|allow|yolo (ask may need /allow)
- Secret paths blocked unless NULLRAY_SECRETS_ALLOW
- Improve/review return owned strings to caller

## Platform tags

| Area | Pattern |
|------|---------|
| term | term_linux / term_bsd / term_windows |
| keys ready | keys_unix (!windows) / keys_windows |
| sandbox | landlock_linux, seccomp_linux, sandbox_stub (!linux) |
| process | process_unix / process_windows |

Do not hide platform imports behind when ODIN_OS in a file every OS compiles. Runtime when is fine inside shared logic already compiled everywhere.

## UI redraw thrash

Forget a.dirty = false after draw -> permanent redraw. Theme change without invalidate -> stale cells. Splash and busy/streaming ticks mark dirty on purpose.
