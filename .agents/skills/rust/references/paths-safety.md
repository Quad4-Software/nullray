# Rust filesystem safety

URLs: [urls.md](urls.md). Prefer
https://docs.rs/cap-std/latest/cap_std/fs/struct.Dir.html and
https://doc.rust-lang.org/std/fs/ for API details.

## TOCTOU

`std::fs` documents that metadata checks followed by use are racy. Another
process can replace a file with a symlink between `exists`/`metadata` and
`open`/`remove_dir_all`.

Mitigations:

- `File::create_new` for exclusive create
- Keep the `File` open for the whole critical section and `fstat` the fd
- Capability-relative APIs (`cap_std::fs::Dir`) so `..` and absolute symlinks
  cannot escape the root

## cap-std pattern

```rust
use cap_std::fs::Dir;
use cap_std::ambient_authority;

let root = Dir::open_ambient_dir("/srv/uploads", ambient_authority())?;
let mut f = root.open("user/data.txt")?;
```

Absolute paths and escaping symlinks error instead of leaving the sandbox.

## Soft links and remove

Directory removal and recursive deletes need care when concurrent renames are
possible. Prefer platform APIs that are race-aware. Do not implement naive
"stat is dir then remove" loops on shared trees.

## Lexical vs resolved

`Path::components` is lexical. `canonicalize` resolves symlinks and requires
the path to exist. For policy checks, decide which model you need. Lexical
prefix checks are not enough when symlinks are allowed.
