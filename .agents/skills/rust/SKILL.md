---
name: rust
description: >
  Rust safe coding patterns, Path/PathBuf footguns, TOCTOU, cap-std rooted
  opens, and edition notes. Use when writing or reviewing Rust, especially
  filesystem, FFI, or untrusted input handling.
---

# Rust

Load this skill for Rust implementation or review. Prefer edition 2024 when the
crate already uses it. Follow `cargo fmt`, `clippy`, and `cargo test` as the
default loop.

## Agent workflow

1. Confirm edition and MSRV from `Cargo.toml`
2. For any user-influenced path, open a trusted directory then use relative
   names (prefer `cap_std::fs::Dir`)
3. Avoid exists-then-open. Operate on fds or capability handles
4. Bound buffers and recursion on untrusted input
5. Document every `unsafe` block invariant before merging
6. Run `cargo fmt`, `cargo clippy`, `cargo test`, and `cargo audit` when deps change

## Path safety

| API | Risk |
|-----|------|
| `Path::exists` | TOCTOU and permission-masking. Prefer `try_exists` then still avoid check-then-act |
| `canonicalize` then `open` | Symlink race between steps |
| String join of user paths | Escape via `..` or absolute segments |

Prefer:

1. Open a trusted directory handle
2. Operate with relative names under that root
3. Use `cap-std` `Dir` (or Linux `openat2` with `RESOLVE_BENEATH`) for untrusted names

Detail: [references/paths-safety.md](references/paths-safety.md).

## Memory and DoS

- Bound collections grown from untrusted input
- Prefer streaming parsers over loading whole bodies
- `unwrap`/`expect` only in tests or truly invariant paths
- Avoid unbounded recursion on attacker-controlled structures

## Unsafe and FFI

- Document every `unsafe` block invariant
- Validate C strings and lengths before slice construction
- Do not expose raw pointers across trust boundaries without ownership rules

## Supply chain

- Commit `Cargo.lock` for binaries
- Use `cargo audit` / advisory checks in CI
- Pin git dependencies to revisions, not floating branches

Pair with [supply-chain](../supply-chain/SKILL.md) and
[attack-surface](../attack-surface/SKILL.md).

## Research URLs

Full list: [references/urls.md](references/urls.md).

- std::path: https://doc.rust-lang.org/std/path/
- std::fs: https://doc.rust-lang.org/std/fs/
- cap-std Dir: https://docs.rs/cap-std/latest/cap_std/fs/struct.Dir.html
- openat2(2): https://man7.org/linux/man-pages/man2/openat2.2.html
- cap-std project: https://github.com/bytecodealliance/cap-std

