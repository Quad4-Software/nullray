# Security caveats

| Claim boundary | Concrete caveat |
|----------------|-----------------|
| OS sandbox | Landlock and seccomp share the host kernel. They do not provide a virtual machine boundary. |
| Linux paths | Canonicalization narrows symlink escapes but cannot remove check-use races. |
| Linux syscalls | The seccomp backend is an amd64 deny list. On arm64 Landlock still applies and seccomp is skipped. It is not a complete syscall allowlist. |
| Network policy | A configured network mode is not proof of network namespace or firewall enforcement. |
| Non-Linux | Warn mode may continue without OS confinement. Read the applied state before making a sandbox claim. |
| Windows | Job Object support is a stub and AppContainer is not implemented. |
| Secrets | Path blocking, environment scrubbing, and redaction reduce exposure. They cannot retract a secret already sent to a provider or printed by an allowed process. |
| MCP pins | A stable tools list detects interface drift. It does not make server output safe, truthful, or free of prompt injection. |
| MCP execution | A trusted server name does not make its child process, dependencies, network peers, or returned text trusted. |
| Read-only ask | `-q` selects ephemeral ask mode with read-only tools. It never enables file writes or shell execution. |
| Permissions | `allow` and `yolo` affect tool approval. They do not widen Landlock paths or turn read-only agent modes into edit mode. |
| Elevated commands | The broker starts before Landlock because `NO_NEW_PRIVS` blocks in-process privilege gain. Approval does not remove command risk. |
| Scanners | `--audit` uses focused pattern scanners. A clean result is not a security proof or a replacement for review and testing. |
| Dependency pins | A digest or commit pin improves repeatability. It does not establish that the pinned artifact is benign. |
| Containers | Rootless users and pinned images reduce risk. Containers still share the host kernel unless a stronger runtime boundary is used. |
| Model output | Provider replies and tool output remain untrusted input. Validate paths, commands, diffs, and generated configuration before use. |
| Checkpoints | File checkpoints help undo supported writes. They are not a complete backup and do not cover every external side effect. |
| Project memory | Durable memory is size-limited and rejects secret-shaped values. Misclassified sensitive text can still be stored. |
| Ops profiles | `NULLRAY_OPS` widens Landlock grants. It is not sandbox off, and it is not a safe cluster-admin mode. |
| Docker sock | Granting docker.sock with unix resolve often equals host Docker root. Prefer audits before compose up. |
| Desktop config RW | `$XDG_CONFIG_HOME` / `~/.config` RW can rewrite shell and compositor autostart. Treat as code execution. |
| Kube allow | `NULLRAY_SECRETS_ALLOW` plus ops kube keeps `KUBECONFIG`. Cluster credentials can reach the model if tools read them. |
| Extra paths | `NULLRAY_SANDBOX_EXTRA_RO` / `EXTRA_RW` accept absolute paths only. Relative paths are ignored. |
| VCS network | Push/pull/fetch and PR tools stay off until `NULLRAY_VCS_NETWORK=1`. Force-push to main/master needs `NULLRAY_VCS_FORCE=1`. |
| fetch_url | Read-only HTTP(S) with size caps. It is not a browser and does not execute JavaScript. |
| TLS verify on | Certificate checks do not make the remote model or MCP server trusted. |
| System CA load | HTTPS needs the host trust store (or SSL_CERT_FILE / SSL_CERT_DIR). Minimal images without ca-certificates fail closed until a PEM path is set. |
| HTTP client | HTTPS prefers HTTP/2 (ALPN h2 via nghttp2) then falls back to HTTP/1.1. Plain http stays HTTP/1.1. TLS 1.2 and 1.3 with X25519MLKEM768 hybrid PQ. Not a browser. No JavaScript. HTTP/3 is not available. |
| HTTP/2 | Application framing only. Same TLS verify and trust model as HTTP/1.1. Not a trust boundary upgrade. |
| HTTP proxy | HTTP(S)_PROXY and related env vars are not honored until a proxy dialer ships. |
| Static Mbed TLS / nghttp2 | Linked into the process address space. Not a sandbox boundary. |
