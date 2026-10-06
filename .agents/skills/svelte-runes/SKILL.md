---
name: svelte-runes
description: >
  Svelte 5 runes ($state, $derived, $effect, $props, $bindable) and shared
  reactive modules in .svelte.ts files. Use when writing or migrating Svelte 5
  components, fixing reactivity bugs, or choosing between derived and effect.
---

# Svelte 5 runes

Load this skill for Svelte 5 component work, runes-mode migration, or shared
reactive state across modules. Prefer official Svelte docs (and MCP docs tools
when available) for API details.

## Agent workflow

1. Confirm the project is on Svelte 5. New files use runes mode only
2. Replace implicit reactivity with `$state` / `$derived` / `$props` as in the
   tables below
3. Prefer `$derived` over `$effect` for values. Effects are browser-only escapes
4. Put shared runes in `.svelte.ts` / `.svelte.js` with stable object exports
5. For Kit SSR, avoid module singletons that hold per-user data
6. Validate with `svelte-check` (and `--tsgo` only after a TypeScript 7 sidecar)

Official rune docs: [references/urls.md](references/urls.md).

## Defaults for new code

Always use runes mode. Prefer modern replacements:

| Old | New |
|-----|-----|
| Implicit `let` reactivity | `$state` |
| `$:` assignments | `$derived` / `$derived.by` |
| `$:` side effects | `$effect` only when no better option |
| `export let` / `$$props` / `$$restProps` | `$props` |
| `<slot>` | snippets + `{@render ...}` |
| `on:` directives | DOM event attributes / callback props |

## Rune roles

| Rune | Use for |
|------|---------|
| `$state` | Values that should invalidate derived values, effects, or the template |
| `$state.raw` | Large objects or arrays that are only reassigned, never mutated |
| `$derived` | Pure values computed from state (expression, not a function) |
| `$derived.by` | Derived logic that needs a function body |
| `$effect` | Browser-only side effects after DOM update. Escape hatch |
| `$props` | Component inputs |
| `$bindable` | Explicit two-way prop binding |
| `$inspect` | Dev-time logging of reactive reads |

Detail and traps: [references/runes.md](references/runes.md).
Migration notes: [references/migration.md](references/migration.md).

## Hard rules

1. Only mark reactive what must be reactive. Plain `let` / `const` for the rest
2. Prefer `$derived` over `$effect` for anything that is a function of state
3. Do not update state inside `$effect` to sync other state
4. Effects never run on the server. Do not wrap effect bodies in `if (browser)`
5. Deep `$state` objects are proxied. Class instances are not. Use class fields
   with `$state` or `$state.raw` for API payloads
6. Do not reassign a `let` export of state across modules. Export an object or
   class instance from a `.svelte.ts` / `.svelte.js` file instead

## Shared state

- Put shared runes in `.svelte.ts` or `.svelte.js`
- For SvelteKit SSR, prefer per-request context over module singletons that hold
  user data (avoids cross-request leaks)
- Kit page stores are legacy. Prefer `$app/state` in modern Kit

## Composition

- Prefer `{@attach ...}` or function bindings over effects that poke the DOM
- Prefer snippets over legacy slots
- Prefer event handlers and bindings over effects that write back into state

## Related

For reusable rune helpers (debounced state, observers, kit params), load
[runed](../runed/SKILL.md).

## Research URLs

Full list: [references/urls.md](references/urls.md).

- What are runes: https://svelte.dev/docs/svelte/what-are-runes
- $state: https://svelte.dev/docs/svelte/$state
- $derived: https://svelte.dev/docs/svelte/$derived
- $effect: https://svelte.dev/docs/svelte/$effect
- Migration guide: https://svelte.dev/docs/svelte/v5-migration-guide
