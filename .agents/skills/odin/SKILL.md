---
name: odin
description: >
  Odin language basics for nullray and general Odin code: packages, allocators,
  errors, build tags, and testing. Use when writing .odin outside narrow
  idioms, or when onboarding to the language. Pair with odin-idioms for repo rules.
---

# Odin

Load this skill for Odin language work. For nullray package layout, ownership,
and platform file tags, also load [odin-idioms](../odin-idioms/SKILL.md).

## Agent workflow

1. Confirm package directory layout (one package name per directory)
2. Use `context.temp_allocator` for scratch. Clone owned strings for storage
3. Match local error style (`err: string` empty means success when that is the convention)
4. Put platform code behind `#+build` files
5. Run `odin test` with `-define:ODIN_TEST_THREADS=1` (or `make test` in this repo)
6. Read [references/language.md](references/language.md) and official overview for syntax edges

## Packages and build

- One package name per directory
- Import via collections: `import "nullray:sandbox"`
- Platform code: `#+build linux` (and friends) in dedicated files
- Tests: `odin test` with `-define:ODIN_TEST_THREADS=1` in this repo

## Allocators

| Allocator | Use |
|-----------|-----|
| `context.allocator` | Long-lived owned data |
| `context.temp_allocator` | Scratch paths, parse buffers, lowercase copies |
| Explicit allocator params | APIs that return owned strings/slices |

Clone strings you store past the current scope. Destroy in matching teardown.
Never return a slice into a stack buffer.

## Errors

Common pattern: `(value, err: string)` or a struct field `err: string`. Empty
string means success when that is the local convention. Prefer `#partial switch`
when cases are intentionally incomplete.

## Paradigms

- Explicit data and procedures over hidden globals
- `#soa` / soa layouts when profiling shows benefit
- Union and enum for closed variants
- `or_else` / `or_return` where the local style already uses them

## Safety notes

- Bounds-check slices. Do not silence checks without a measured reason
- Integer casts can truncate. Validate sizes from the wire
- C FFI: match calling conventions and lifetimes carefully

Detail: [references/language.md](references/language.md).
Repo map: [odin-idioms](../odin-idioms/SKILL.md), [memory](../memory/SKILL.md).

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Overview: https://odin-lang.org/docs/overview/
- Packages: https://odin-lang.org/docs/packages/
- FAQ: https://odin-lang.org/docs/faq/
- GitHub: https://github.com/odin-lang/Odin

