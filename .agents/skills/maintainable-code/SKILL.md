---
name: maintainable-code
description: >
  Produce small, testable, maintainable changes: pure cores, explicit errors,
  stable APIs, no drive-by refactors. Use before large edits or when agent
  output risks becoming unreviewable.
---

# Maintainable code

Load this skill for implementation quality. Pair with
[modular-design](../modular-design/SKILL.md),
[software-testing](../software-testing/SKILL.md),
[error-handling](../error-handling/SKILL.md), and
[agent-footguns](../agent-footguns/SKILL.md).

## Defaults

1. Read existing patterns before writing
2. Smallest diff that meets the ask
3. Pure functions at the center, IO at the edges
4. Explicit errors over hidden panics / swallowed catches
5. Names match behavior. Delete dead code you replace
6. Tests name an oracle (example, property, or characterization)

## Structure

| Prefer | Avoid |
|--------|-------|
| One job per file/package | Godfiles and kitchen-sink utils |
| Dependency inversion at boundaries | Domain importing frameworks |
| Table-driven cases | Copy-paste test twins |
| Feature flags / registries | Ever-growing central switches |

## API stability

- Do not break public APIs unless the task requires it
- Prefer additive changes
- Document behavioral changes in user-facing notes when relevant

## nullray specifics

- Follow [odin-idioms](../odin-idioms/SKILL.md) and [memory](../memory/SKILL.md)
- Respect [structure](../structure/SKILL.md) line limits
- Verify with `make test` when editing code

URLs: [references/urls.md](references/urls.md).
