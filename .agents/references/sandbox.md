# Sandbox capability matrix

| Capability | Linux | Windows | macOS |
|------------|-------|---------|-------|
| Filesystem confinement | Landlock when supported by the kernel | Not applied in the current build | Not available |
| Syscall filtering | seccomp deny list on amd64 | Not available | Not available |
| Process containment | `NO_NEW_PRIVS` plus seccomp limits | Job Object helper is a stub | Not available |
| AppContainer | Not applicable | Not implemented | Not applicable |
| Secret path blocking and output redaction | Application policy | Application policy | Application policy |
| Warn mode | Continues if an OS control fails | Continues without Job Object isolation | Continues without OS isolation |
| Strict mode | Fails if a requested control fails | Fails while the Job Object helper is unavailable | Fails because no backend exists |
| Doctor report | Mode, applied state, Landlock ABI, seccomp support | Backend availability | Unsupported backend |
| Host man tools | `read_man` and `apropos` | Unavailable | Unavailable |

`NULLRAY_SANDBOX=warn` is the soft mode and the default. `strict` and `on` request fail-closed startup. `off` disables OS sandbox application.

Landlock controls path access for the process after rules are applied. The seccomp filter is a deny list, not a syscall allowlist. Network mode is represented in policy state, but the current backend does not provide complete network namespace isolation.

The Windows Job Object and AppContainer rows describe separate controls. A Job Object can constrain process lifetime and resources. AppContainer can provide a security boundary. Neither is active in the current build.
