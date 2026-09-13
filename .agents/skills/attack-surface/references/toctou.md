# TOCTOU and path races

## Pattern

```
if path_is_safe(user_path):
    open(user_path)  # attacker swaps path here
```

Between the check and the use, a privileged program can be redirected via
symlink replacement, rename, or mount tricks.

## Mitigations

| Approach | Notes |
|----------|-------|
| Open relative to a directory fd | `openat`, `openat2(RESOLVE_BENEATH)` |
| `O_NOFOLLOW` / no-symlink policy | When symlinks must be rejected |
| Exclusive create (`O_EXCL`) | Avoids replace-during-create |
| Operate on the fd after open | fstat, fchmod, read via fd |
| Private directories with safe perms | Reduces who can race |

Canonicalize-then-open without holding a directory fd remains racy.

CWE-367: https://cwe.mitre.org/data/definitions/367.html
openat2: https://man7.org/linux/man-pages/man2/openat2.2.html

## Related footguns

- Temporary files in shared `/tmp` without `O_EXCL` and restrictive umask
- Dropping privileges after opening a user-controlled path
- Recursive delete that follows replaced directories
