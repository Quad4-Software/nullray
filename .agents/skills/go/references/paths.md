# Go path packages

## Rule

| Package | Job |
|---------|-----|
| `path` | Slash-separated logical names (URLs, archive members, virtual trees) |
| `path/filepath` | Operating system filesystem paths |

Never call `path.Join` or `path.Clean` on OS paths. On Windows those helpers
do not understand backslashes or volume names the way `filepath` does.

## Safe join under a root

1. Resolve a trusted root with `filepath.Abs` / `filepath.Clean`
2. Join user segments with `filepath.Join(root, ...)`
3. Clean the result
4. Confirm the cleaned path is still under the root (prefix check after
   ensuring a directory separator boundary)
5. Open with the cleaned path, or better with `os.OpenRoot` / `os.Root` APIs
   when the Go version and platform support rooted opens

Lexical prefix checks alone fail if the root is not cleaned the same way as
the candidate, or if trailing separators differ.

## TOCTOU

`os.Stat` then `os.Open` is a race. Prefer:

- Open first, then `Stat` the file descriptor / `os.File`
- `os.OpenRoot` and relative opens under that root
- Exclusive create flags when creating files

## Archives and URLs

Zip or tar member names are logical paths. Use `path` (or a dedicated archive
sanitizer) to reject `..` and absolute members before writing under a root.
Do not feed raw member names to `filepath.Join` without sanitizing.

## Checklist

1. Identify whether the string is an OS path or a logical path
2. Pick `filepath` or `path` accordingly
3. Bound size and depth of user-controlled path trees
4. Pair with [attack-surface](../../attack-surface/references/toctou.md)
