---
name: landlock-seccomp
description: >
  Linux Landlock LSM and seccomp-bpf sandboxing: ABI negotiation, filesystem
  and network rules, NO_NEW_PRIVS, allowlist vs denylist filters. Use when
  implementing or reviewing process self-restriction, or explaining how
  nullray sandbox controls map to kernel APIs.
---

# Landlock and seccomp-bpf

Load this skill when implementing Linux self-sandboxing, reviewing syscall or
path policy, or explaining kernel mechanisms behind nullray isolation. For
product knobs (`NULLRAY_SANDBOX`, ops profiles, doctor), also load
[sandbox](../sandbox/SKILL.md).

## Agent workflow

1. Confirm the host is Linux with Landlock enabled (kernel docs / `dmesg`)
2. Query ABI at runtime. Do not hard-code the build machine's ABI
3. Apply Landlock path (and optional net) rules with handled-bit masking
4. Set `NO_NEW_PRIVS` before restrict when required by the ABI path you use
5. Layer seccomp. Prefer allowlists. Treat denylists as defense in depth only
6. Fail closed in strict product modes when a required control cannot apply
7. Map claims to [references/urls.md](references/urls.md) before writing docs

## What each control does

| Control | Enforces | Does not enforce |
|---------|----------|------------------|
| Landlock | Path hierarchy access, optional TCP/UDP ports, some IPC scopes | Full network namespaces, syscall semantics |
| seccomp-bpf | Which syscalls (and sometimes args) may run | Path-aware open decisions |
| `NO_NEW_PRIVS` | No privilege gain across exec / setuid | Replacement for Landlock or seccomp |

They compose. Landlock answers "which files and ports". seccomp answers "which
syscalls". Neither replaces containers, VMs, or system LSMs (AppArmor/SELinux)
for multi-tenant hard isolation.

## Landlock workflow

1. Query ABI: `landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION)`
2. Mask `handled_access_fs` / `handled_access_net` / `scoped` to what that ABI
   supports (best-effort pattern from kernel docs)
3. `landlock_create_ruleset` with the masked attr
4. Add path rules (`LANDLOCK_RULE_PATH_BENEATH`) and optional net port rules
5. Mask each rule's `allowed_access` against handled bits. Skip empty rules
6. Set `NO_NEW_PRIVS` (or use ABI flags that set it on restrict)
7. `landlock_restrict_self`
8. Restrictions inherit to children of the thread that applied them

ABI table and rights: [references/landlock-abi.md](references/landlock-abi.md).

## seccomp-bpf workflow

Prefer an allowlist: default `SCMP_ACT_ERRNO(EPERM)` (or KILL), then allow only
syscalls the workload needs. Deny lists are easier to ship and easier to bypass
when new dangerous calls appear or ABIs alias numbers (see x32 bit caveats).

libseccomp is the usual builder. Hand-written classic BPF is fine for small
fixed deny lists (nullray uses that shape on amd64).

Detail: [references/seccomp.md](references/seccomp.md).

## Claim limits

- Soft/warn modes may continue without confinement when the kernel lacks support
- A denylist seccomp policy is not a proof of safety
- Landlock without network ABI support does not filter connect/bind
- Strict product modes should fail closed when a required control cannot apply

## nullray map

| Kernel piece | Code |
|--------------|------|
| Landlock apply | `nullray/sandbox/landlock_linux.odin` |
| seccomp deny list | `nullray/sandbox/seccomp_linux.odin` |
| Capability claims | `.agents/references/sandbox.md` |
| Product skill | [sandbox](../sandbox/SKILL.md) |

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Landlock userspace API: https://docs.kernel.org/userspace-api/landlock.html
- landlock(7): https://man7.org/linux/man-pages/man7/landlock.7.html
- Seccomp BPF: https://docs.kernel.org/userspace-api/seccomp_filter.html
- libseccomp: https://github.com/seccomp/libseccomp

