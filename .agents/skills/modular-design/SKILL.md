---
name: modular-design
description: >
  No-godfile modular design: single responsibility files, extension points,
  stable public APIs, and split strategies for oversized modules. Use when
  creating packages, refactoring large files, or reviewing extensibility.
---

# Modular design

Load this skill when adding packages, splitting oversized files, or designing
extension points. For nullray Odin line limits, also load
[structure](../structure/SKILL.md).

## Agent workflow

1. Name the capability the new code owns
2. Check whether an existing module already owns that capability
3. If a file shows godfile signals, follow [references/godfiles.md](references/godfiles.md)
4. Prefer registries / ports over growing a central switch
5. Keep public surfaces thin. Hide helpers with the owner
6. Re-run tests after each extract. For nullray, `make test` includes structure checks

## Goals

- One clear job per file and package
- New behavior lands in new modules or adapters, not by fattening a center file
- Public surfaces stay small and stable
- Callers depend on contracts, not internals

## Godfile signals

Treat a file as a godfile when several of these are true:

| Signal | Example |
|--------|---------|
| Many unrelated responsibilities | Parse, network, UI, and persistence in one file |
| High fan-in and fan-out | Everything imports it and it imports everything |
| Hard to test in isolation | Needs full app bootstrap for a unit check |
| Change risk | Any feature touches the same file |
| Size | Past project max lines (nullray default 400, warn 250) |

Split strategy: [references/godfiles.md](references/godfiles.md).

## Modular rules

1. Name packages after domains or capabilities, not after layers alone
2. Keep a thin public entry. Hide helpers in the same package or a private file
3. Prefer composition over inheritance trees
4. Extension: register plugins, tables of handlers, or ports. Avoid editing a
   central switch for every new case when a registry works
5. Shared code holds policy-free primitives. Business rules stay with the owner
6. Do not create a `utils` dumping ground. Name the capability

## Extensibility checklist

- Can a new case ship without editing the core loop?
- Can tests substitute adapters without rewriting production types?
- Can a file be understood without loading half the tree?
- Does deleting a feature mostly delete one slice?

## Anti-patterns

- Premature micro-packages that force navigation without boundaries
- Circular imports papered over with late imports
- "Temporary" god objects that collect more fields each sprint
- Copy-paste modules that diverge silently

## Verify

- For nullray: `make test` includes structure godfile checks on Odin sources
- Elsewhere: enforce size and import rules in CI when the repo has them
- After a split, keep public APIs stable unless the task requires a break

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Hexagonal architecture: https://alistair.cockburn.us/hexagonal-architecture/
- Clean Architecture: https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html
- Go package names: https://go.dev/blog/package-names
- Rust API guidelines: https://rust-lang.github.io/api-guidelines/

