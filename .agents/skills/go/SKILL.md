---
name: go
description: >
  Go 1.27 language and toolchain, generic methods, path and filepath safety,
  and modern stdlib notes. Use when writing or reviewing Go, choosing toolchain
  versions, or handling filesystem paths securely.
---

# Go 1.27

Load this skill for Go code, generics, path handling, or toolchain questions.
Release: August 2026. Compatibility promise holds. Confirm details against
https://go.dev/doc/go1.27 before asserting version facts.

## Agent workflow

1. Confirm the module `go` line and installed toolchain (`go version`)
2. For language changes, read [references/generics.md](references/generics.md)
   and the official notes linked in [references/urls.md](references/urls.md)
3. For filesystem work, apply [references/paths.md](references/paths.md) before
   writing Join/Clean/Open logic
4. Prefer `filepath` for OS paths and rooted opens when available
5. Run `go test` (and `go vet` via the default `go test` path) on touched packages
6. Pair path and dependency risks with attack-surface and supply-chain skills

## Language (1.27)

| Change | Detail |
|--------|--------|
| Generic methods | Concrete methods may declare type parameters. Interfaces may not |
| Struct literal keys | Any valid field selector, including embedded fields |
| Function type inference | Generic funcs infer in composites, conversions, and channel sends |

```go
func (r *Rand) N[Int intType](n Int) Int

func (List[E]) Map[R any](f func(E) R) List[R]
```

Generic methods do not implement interface methods. Prefer package-level
generic funcs when an interface must be satisfied.

Detail: [references/generics.md](references/generics.md).

## Paths

| Package | Use |
|---------|-----|
| `path` | Slash-separated logical paths (URLs, zip members). Never for OS files |
| `path/filepath` | OS filesystem paths |

Prefer `filepath.Join`, `Clean`, `Rel`, `WalkDir`. Never `path.Join` for disk.
Validate user paths under a trusted root. See [references/paths.md](references/paths.md).

## Toolchain highlights

- `go test` runs `stdversion` vet by default
- `go doc pkg@version` and `go doc -ex`
- `go mod tidy` consolidates require blocks for `go 1.27` modules
- Size-specialized malloc for small objects (opt out `GOEXPERIMENT=nosizespecializedmalloc`)
- `goroutineleak` pprof profile generally available
- `encoding/json/v2` and `encoding/json/jsontext` in stdlib
- `crypto/mldsa`, TLS MLKEM1024 / ML-DSA

Green Tea GC became default in Go 1.26. The 1.26 `nogreenteagc` opt-out is gone
in 1.27.

## Security posture

- Vendor or pin modules for offline / reproducible builds (`-mod=vendor`)
- Treat path checks plus later open as TOCTOU-prone
- Cap readers, decoders, and recursion (XML, JSON, tar) against DoS
- Pair with [supply-chain](../supply-chain/SKILL.md) and [attack-surface](../attack-surface/SKILL.md)

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Release notes: https://go.dev/doc/go1.27
- Blog: https://go.dev/blog/go1.27
- Generic methods: https://go.dev/blog/generic-methods
- filepath: https://pkg.go.dev/path/filepath

