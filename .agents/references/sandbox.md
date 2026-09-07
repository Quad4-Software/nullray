# Sandbox capability matrix

| Capability | Linux | Windows | macOS |
|------------|-------|---------|-------|
| Filesystem confinement | Landlock when supported by the kernel | Not applied in the current build | Not available |
| Syscall filtering | seccomp deny list on amd64 (skipped on arm64) | Not available | Not available |
| Process containment | `NO_NEW_PRIVS` plus seccomp limits | Job Object helper is a stub | Not available |
| AppContainer | Not applicable | Not implemented | Not applicable |
| Secret path blocking and output redaction | Application policy | Application policy | Application policy |
| Ops profiles (`NULLRAY_OPS`) | desktop / docker / kube / full widen allowlists | Ignored for OS confinement | Ignored for OS confinement |
| Extra path env | `NULLRAY_SANDBOX_EXTRA_RO` / `EXTRA_RW` absolute paths | Same env parsing | Same env parsing |
| Docker sock unix resolve | Landlock ABI 9+ `RESOLVE_UNIX` on sock path only | Not available | Not available |
| Warn mode | Continues if an OS control fails | Continues without Job Object isolation | Continues without OS isolation |
| Strict mode | Fails if a requested control fails | Fails while the Job Object helper is unavailable | Fails because no backend exists |
| Doctor report | Mode, extras, ops, Landlock ABI, seccomp support | Backend availability | Unsupported backend |
| Host man tools | `read_man` and `apropos` | Unavailable | Unavailable |

`NULLRAY_SANDBOX=warn` is the soft mode and the default. `strict` and `on` request fail-closed startup. `off` disables OS sandbox application.

Prefer `NULLRAY_OPS=desktop,docker` (or `full` with explicit `NULLRAY_SECRETS_ALLOW` for kube) over `NULLRAY_SANDBOX=off`.

Landlock controls path access for the process after rules are applied. Unix socket connect to docker.sock needs ABI 9 and an explicit sock grant. The seccomp filter is a deny list, not a syscall allowlist. Network mode is represented in policy state, but the current backend does not provide complete network namespace isolation.

The Windows Job Object and AppContainer rows describe separate controls. A Job Object can constrain process lifetime and resources. AppContainer can provide a security boundary. Neither is active in the current build.

Headless elevate on servers: use `NULLRAY_ELEVATE=ticket` with a prior TUI approval, or `NULLRAY_ASKPASS` pointing at an external askpass. Passwords never enter tool results.
