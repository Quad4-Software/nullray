# Landlock ABI map

Source of truth: https://docs.kernel.org/userspace-api/landlock.html

Query the running ABI at runtime. Never assume the build machine's kernel.

## ABI milestones

| ABI | Approx kernel | Adds |
|-----|---------------|------|
| 1 | 5.13 | Filesystem path hierarchy rights |
| 2 | 5.19 | `LANDLOCK_ACCESS_FS_REFER` (link/rename across trees) |
| 3 | 6.2 | `LANDLOCK_ACCESS_FS_TRUNCATE` |
| 4 | 6.7 | TCP bind/connect port rules |
| 5 | 6.10 | `LANDLOCK_ACCESS_FS_IOCTL_DEV` |
| 6 | 6.12 | Scope: abstract UNIX sockets, signals |
| 9 | later | `LANDLOCK_ACCESS_FS_RESOLVE_UNIX` (UNIX socket path resolve) |
| 10 | later | UDP bind / connect-send port rules |

Higher ABIs continue to extend. Always fall through a compatibility switch that
clears unknown bits for older kernels.

## Compatibility switch (idea)

```
abi = landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION)
switch abi {
  case 1: clear REFER
  case 2: clear TRUNCATE
  case 3: clear NET TCP
  case 4: clear IOCTL_DEV
  case 5: clear SCOPE bits
  case 6..8: clear RESOLVE_UNIX
  case 9: clear UDP net bits
}
```

Then create the ruleset and AND each rule's allowed access with handled access.

## Filesystem rights (conceptual)

Handled rights are denied by default unless a path beneath rule grants them.
Typical RO grant: read file, read dir, execute. Typical RW grant adds write,
remove, make-*, truncate when available.

Open directories with `O_PATH | O_CLOEXEC` when filling
`landlock_path_beneath_attr`.

## Network and scope

- TCP port rules need ABI 4+
- UDP rules need ABI 10+
- Scoping abstract UNIX and signals needs ABI 6+
- DNS-style clients often need TCP 53 connect plus UDP send to 53 and bind UDP 0

## Inheritance

New threads from `clone` inherit the Landlock domain of the applying thread.
Sibling threads that never called `landlock_restrict_self` are not retroactively
confined. Apply before workers start, or apply in each thread intentionally.

## Forward compatibility

Landlock will not silently tighten an existing ruleset across kernel upgrades
in a way that breaks the userspace contract for handled rights. Still, new
rights appear over time. Handled-bit negotiation keeps older kernels working.
