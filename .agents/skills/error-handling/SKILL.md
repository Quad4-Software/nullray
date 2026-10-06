---
name: error-handling
description: >
  Explicit error returns, typed failures, and boundary mapping for maintainable
  APIs. Use when designing Go/Odin/TS error paths or fixing swallowed failures.
---

# Error handling

Load with [maintainable-code](../maintainable-code/SKILL.md). Prefer explicit
results over panics and silent catches.

## Defaults

| Do | Do not |
|----|--------|
| Return errors / Result types at package edges | Swallow and continue |
| Add context once at the boundary | Wrap the same error five times |
| Log or surface at the outermost handler | Print and return nil |
| Fail closed for authz / parse of untrusted input | Best-effort parse into "safe" defaults |
| Keep error strings free of secrets | Embed tokens, paths with home, or PII |

## Language notes

- **Odin**: check allocator and syscall errors. Clone strings you own. See
  [odin-idioms](../odin-idioms/SKILL.md) and [memory](../memory/SKILL.md)
- **Go**: wrap with `%w`. Prefer sentinel + `errors.Is` / `As` over string match
- **TypeScript**: typed results or thrown domain errors at boundaries. Avoid
  empty `catch {}`

## Agent checklist

1. Grep for empty catch / ignored `_ =` without a comment that names why
2. Ensure new public APIs document failure modes
3. Add a test that forces the failure path (see [software-testing](../software-testing/SKILL.md))

URLs: [references/urls.md](references/urls.md).
