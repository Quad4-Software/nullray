# Splitting godfiles

## Process

1. List responsibilities in the oversized file (one line each)
2. Group by change frequency and ownership
3. Extract the group with the clearest boundary first
4. Move types and helpers with the behavior that owns them
5. Leave a thin facade only when callers need a stable import path
6. Re-run tests after each extract

## Split shapes

| Shape | When |
|-------|------|
| By feature / slice | Use cases already cluster in the file |
| By protocol / adapter | HTTP, CLI, and DB logic share a core |
| By lifecycle | Init, runtime loop, and teardown are distinct |
| By platform | OS or arch build-tagged files |
| By purity | Pure logic out of IO-heavy drivers |

## Keep together

- Invariants that must change atomically
- Private helpers used by one owner only
- Generated code that tools expect as one unit (document allow_godfile)

## Naming after a split

Prefer concrete names: `landlock_linux.odin`, `session_trim.odin`,
`order_cancel.ts`. Avoid `helpers2`, `misc`, `manager`.

## Extensible cores

When the core dispatches work:

```
registry[name] = handler
core calls registry, does not switch on every name
```

New handlers register. The core file stops growing with each feature.

## nullray notes

- Read `.nullray/policy.json` when present for max lines
- `allow_godfile` only with explicit user acceptance or unsplittable generated code
- `NULLRAY_STRUCTURE=0` is a deliberate workspace bypass, not a habit
