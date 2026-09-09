# Security caveats

| Claim boundary | Concrete caveat |
|----------------|-----------------|
| OS sandbox | Landlock and seccomp share the host kernel. They do not provide a virtual machine boundary. |
| Linux paths | Canonicalization narrows symlink escapes but cannot remove check-use races. |
| Linux syscalls | The seccomp backend is an amd64 deny list. On arm64 Landlock still applies and seccomp is skipped. It is not a complete syscall allowlist. |
| Network policy | A configured network mode is not proof of network namespace or firewall enforcement. |
| Non-Linux | Warn mode may continue without OS confinement. Read the applied state before making a sandbox claim. |
| Windows | Job Object with KILL_ON_JOB_CLOSE is applied when sandbox is on. AppContainer is not implemented. FS policy is not Landlock-equivalent. |
| HTTP proxy | HTTP(S)_PROXY / ALL_PROXY / NO_PROXY are honored (CONNECT for HTTPS). Proxy URL scheme must be `http://`. TLS-to-proxy is not supported (`https://` proxy URLs are ignored). |
| Provider failover | NULLRAY_PROVIDER_FALLBACKS retries chat on dead-key/payment errors. It does not invent credits or bypass billing. |
| MCP / trust | Tool and MCP results are framed as UNTRUSTED_DATA. Remote/untrusted workspaces need NULLRAY_WORKSPACE_TRUST=1 (or MCP_ALLOW_ANY) before MCP connect. |
| Secrets | Path blocking, environment scrubbing, and redaction reduce exposure. They cannot retract a secret already sent to a provider or printed by an allowed process. |
| MCP pins | A stable tools list detects interface drift. It does not make server output safe, truthful, or free of prompt injection. |
| MCP execution | A trusted server name does not make its child process, dependencies, network peers, or returned text trusted. |
| Read-only ask | `-q` selects ephemeral ask mode with read-only tools. It never enables file writes or shell execution. |
| Permissions | `allow` and `yolo` affect tool approval. They do not widen Landlock paths or turn read-only agent modes into edit mode. |
| Elevated commands | The broker starts before Landlock because `NO_NEW_PRIVS` blocks in-process privilege gain. Approval does not remove command risk. |
| Scanners | `--audit` / audit_* use focused pattern scanners (secrets, injection-ish sinks, Dockerfile/Compose/Actions hygiene, lock files). A clean result is not a security proof or a replacement for review and testing. |
| Hunt sampling | Static profiles set temperature/top_p for the turn. auto in print mode runs explore then oracle as two provider passes. Sampling does not prove findings. Confirm with an oracle. |
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
| fetch_url | Read-only HTTP(S) with size caps, private IPv4/IPv6 SSRF checks, and optional `NULLRAY_FETCH_ALLOW`. Not a browser. No JavaScript. |
| Speculative tools | Speculative allowlisted reads are on by default (NULLRAY_SPECULATE=0 disables). They do not remove TOCTOU, widen Landlock, or make PreToolUse hooks safe if they are not idempotent. PreToolUse may fire early on speculated tools. |
| LID excerpts | Envelope excerpts are privacy-reduced (secret-aware stubs). They are not a proof that artifacts are free of secrets. |
| Artifact ids | Artifact ids are workspace-scoped under `.nullray/artifacts`. They are not secret capability tokens. |
| Session store | New sessions write `.msgpack`. Old `.jsonl` still loads. Export is JSONL. Transcripts may retain sensitive task text at rest under the config/session store. |
| Peer teams | Subagent peer messages are size-capped and unframed unless teams mode is on. Treat as untrusted. |
| Gate | `--gate` / `NULLRAY_GATE` / `/gate` 0..3 caps tool capability. Always-deny shell patterns still hard-block at gate 3. |
| Shell net | curl/wget/nc need `/allow` or `NULLRAY_SHELL_NET=1` even under yolo. |
| Hooks trust | Workspace `.nullray/hooks.json` rewritten mid-session needs `/hooks trust` or `NULLRAY_HOOKS_TRUST=1` (trust handoff). |
| Sandbox escape | Landlock is not AF_UNIX/D-Bus isolation. docker.sock grants often equal host Docker root. systemd-run/busctl/gdbus are always-denied. |
| AGENTS.md | Untrusted workspaces wrap AGENTS/CLAUDE/nullray.md as UNTRUSTED_DATA until `NULLRAY_WORKSPACE_TRUST=1`. |
| TLS verify on | Certificate checks do not make the remote model or MCP server trusted. |
| System CA load | HTTPS needs the host trust store (or SSL_CERT_FILE / SSL_CERT_DIR). Minimal images without ca-certificates fail closed until a PEM path is set. |
| HTTP client | HTTPS prefers HTTP/2 (ALPN h2 via nghttp2) then falls back to HTTP/1.1. Plain http stays HTTP/1.1. TLS 1.2 and 1.3 with X25519MLKEM768 hybrid PQ. Not a browser. No JavaScript. HTTP/3 is not available. |
| HTTP/2 | Application framing only. Same TLS verify and trust model as HTTP/1.1. Not a trust boundary upgrade. |
| Static Mbed TLS / nghttp2 | Linked into the process address space. Not a sandbox boundary. |
