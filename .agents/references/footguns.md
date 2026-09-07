# Footguns

Mistakes that burn time in this tree. Pair with memory and tui skills.

## Never

| Mistake | Why |
|---------|-----|
| Keep temp_allocator pointers across frames, jobs, HTTP, or threads | loop_run free_all each iteration |
| free_all(temp) inside SSE/HTTP callbacks | frees curl URL/POSTFIELDS and tools_json mid-request |
| OpenRouter provider.ignore on non-429 retries | 502/503 previous_errors can ignore every upstream |
| Write ANSI into Buffer cells | present owns escapes |
| Skip CELL_WIDE_CONT after wide runes | corrupt diff and cursor |
| Use len(s) as display columns | use rune_cols / string_cols |
| Merge plat backends into one untagged file | #+build files only |
| Expect splash keys to queue | input dropped while splash_active |
| Rely on binds_resolve for Esc-stop | busy cancel hardcoded, stop_agent unused |
| Double-free nested owned strings | delete once, clone on replace |
| destroy_session_infos with wrong allocator | match list_sessions allocator (banner used temp then heap delete) |
| Skip destroy pairs | app_destroy, loop_close, buffer_destroy, registry_destroy, session_destroy, tools.registry_destroy, mcp.registry_destroy |
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

Permanent: App (owns provider, tools, and mcp registries), Session, Provider.

## Sandbox

Modes: Off / Warn (default) / Strict via NULLRAY_SANDBOX.

| OS | Warn | Strict |
|----|------|--------|
| Linux | landlock/seccomp fail continues with warn | fail Result.ok=false |
| other | skip | fail sandbox requires linux |

Stub: sandbox_stub.odin #+build !linux. apply uses when ODIN_OS == .Linux for runtime branch.

Landlock sets NO_NEW_PRIVS. Elevated cmds need the pre-sandbox broker (nullray/elevate), not in-process sudo. Never put passwords in shell args or expect them in tool results. After elevation_locked / auth_cancelled, stop looping elevate.

## Session / tools / agent

- Messages: clone content, destroy_message / session_destroy
- Pending events: clone text/name/reasoning, delete on consume/destroy
- Tool (out, err): empty err means success, clone to caller allocator
- Args JSON on temp, clone extracted strings out
- Tool mode gating uses an explicit mode string (ask|plan|review|edit), not NULLRAY_MODE env
- Tool.kind (Read/Write/Shell/Mcp) drives allowlists, not tool name tables
- Streaming goes through Provider.stream, not a direct openai_chat_stream call from agent
- Perms: NULLRAY_PERMS ask|allow|yolo (ask may need /allow)
- Print/edit needs allow or yolo (no interactive /allow)
- Skill name from replace_all must be cloned when was_allocation is false
- Secret paths blocked unless NULLRAY_SECRETS_ALLOW
- Improve/review return owned strings to caller
- Plan artifacts: agent.save_plan_artifact, default under .nullray/plans/
- Subagent spawn never git stash. Lease writes before edit. Worktree children jail to worktree path.
- NULLRAY_SUBAGENTS=0 omits task from tools JSON. Apply needs verify-all unless --force.
- agent.register_subagent_runner before spawn (app_init / print)
- Child transcripts stay on disk digests only in parent context

## Platform tags

| Area | Pattern |
|------|---------|
| term | term_linux / term_bsd / term_windows |
| keys ready | keys_unix (!windows) / keys_windows |
| sandbox | landlock_linux, seccomp_linux, sandbox_stub (!linux) |
| process | process_unix / process_windows |

Do not hide platform imports behind when ODIN_OS in a file every OS compiles. Runtime when is fine inside shared logic already compiled everywhere.

## UI redraw thrash

Forget a.dirty = false after draw -> permanent redraw. Theme change without invalidate -> stale cells. Splash keeps dirty for animation. Busy/stream redraws on session deltas or SPINNER_FRAME_MS cadence, not every poll tick.
