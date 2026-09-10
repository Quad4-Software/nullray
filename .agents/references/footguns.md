# Footguns

Mistakes that burn time in this tree. Pair with memory and tui skills.

## Never

| Mistake | Why |
|---------|-----|
| Keep temp_allocator pointers across frames, jobs, HTTP, or threads | loop_run free_all each iteration |
| free_all(temp) inside SSE/HTTP callbacks | frees HTTP POST body / stream URL pointers and tools_json mid-request |
| OpenRouter provider.ignore on non-429 retries | 502/503 previous_errors can ignore every upstream |
| Write ANSI into Buffer cells | present owns escapes |
| Skip CELL_WIDE_CONT after wide runes | corrupt diff and cursor |
| Use len(s) as display columns | use rune_cols / string_cols |
| Merge plat backends into one untagged file | #+build files only |
| Expect splash keys to queue | input dropped while splash_active |
| Rely on hardcoded Esc-stop only | busy stop is binds_resolve Stop_Agent (stop= in keys.ini) |
| Leave pasting true after cancel | clear pasting on cancel and submit |
| Mutate a.input from improve worker | post pending, apply in app_on_tick |
| Double-free nested owned strings | delete once, clone on replace |
| destroy_session_infos with wrong allocator | match list_sessions allocator (banner used temp then heap delete) |
| Skip destroy pairs | app_destroy, loop_close, buffer_destroy, registry_destroy, session_destroy, tools.registry_destroy, mcp.registry_destroy |
| ODIN_TEST_THREADS != 1 with shared globals | Makefile sets =1 |
| Strict sandbox on non-Linux | fails with sandbox requires linux |
| Label OpenRouter /credits as turn cost | credits are balance remaining, not generation cost |
| Invent cost_usd from token counts | only parse provider cost fields, else cost_known=false |
| Expect term_emergency_restore CSI in print | gated on g_em_active (raw mode) |
| Index the live codebase into RAG vectors | use grep/locate/repo_map; vectors are for memory and LID artifacts only |
| Auto-evolve nullray core from agent traces | reviewed human edits only; no Ouroboros-style self-patch |
| Add ANN/FAISS for .nullray/rag | linear scan is enough under RAG_MAX_CHUNKS |
| Set NULLRAY_VERIFY=false expecting /bin/false | false/off/0 disable verify; use an explicit shell command instead |
| Treat shell output without exit_code= as success | verify fails closed when the trailer is missing |
| Index full multi-MB LID artifacts into RAG | only the first RAG_ARTIFACT_INDEX_CHARS are embedded |

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
- Done Contract gate includes Steps (not only Verify/Success/Budget)
- Incomplete plans get a repair nudge and are not saved. Prefer ending the turn with only the markdown plan.
- Lean print hides non-core tools unless listed (scaffold, list_scaffolds, audit_structure are in lean core).
- Step anchoring after approve injects one current step. Number Steps (1. 2. 3.) for reliable parsing.
- Print-strict is opt-in (NULLRAY_PRINT_STRICT / --print-strict). Default print-smoke stays exit 0 on soft incompleteness.
- Usage files next to sessions may show project intensity. hide-sensitive hides UI cost/credits only.
- Ephemeral print skips .usage.jsonl unless NULLRAY_USAGE_PERSIST=1
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
