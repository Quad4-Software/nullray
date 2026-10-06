# seccomp-bpf notes

Kernel docs: https://docs.kernel.org/userspace-api/seccomp_filter.html
libseccomp: https://github.com/seccomp/libseccomp
Full URL table: [urls.md](urls.md).

## Allowlist vs denylist

Kernel docs and Docker/Kubernetes practice prefer allowlists:

1. Default action: `SCMP_ACT_ERRNO(EPERM)` or `SCMP_ACT_KILL_PROCESS`
2. Explicitly allow required syscalls
3. Optionally allow with argument filters (for example personality values)

Denylist (default allow, deny dangerous numbers) is weaker:

- New syscalls may be dangerous and still allowed
- Number aliasing (x32 `__X32_SYSCALL_BIT`) can bypass naive deny lists
- Multiplexed calls differ by architecture

nullray ships a small amd64 denylist as defense in depth beside Landlock. Treat
that as complementary, not as a complete syscall policy.

## libseccomp sketch

```
ctx = seccomp_init(SCMP_ACT_ERRNO(EPERM))
seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0)
...
seccomp_load(ctx)
```

Use `seccomp_rule_add` (best-effort arch rewriting) unless you need exact
numbers via `seccomp_rule_add_exact`.

## Development loop

1. Start with `SCMP_ACT_LOG` or a tracing profile to discover needed calls
2. Build the allowlist from real workloads and tests
3. Switch to ERRNO or KILL
4. Regression-test across arches you claim to support

## Actions

| Action | Meaning |
|--------|---------|
| `SCMP_ACT_ALLOW` | Permit |
| `SCMP_ACT_ERRNO(e)` | Fail with errno |
| `SCMP_ACT_KILL_THREAD` / `KILL_PROCESS` | Terminate |
| `SCMP_ACT_LOG` | Allow and log (audit / develop) |
| `SCMP_ACT_TRAP` | SIGSYS |

## Compose with Landlock

- Deny `ptrace`, module load, `kexec`, raw `bpf`, namespace escapes in seccomp
  when the product does not need them
- Still grant filesystem paths via Landlock, because seccomp cannot express
  "open this tree but not that one"

## Containers

Docker and Kubernetes RuntimeDefault profiles are allowlists with a curated
syscall set. Prefer them over `unconfined` for workloads that can tolerate them.
Fine-grained profiles need workload-specific discovery.
