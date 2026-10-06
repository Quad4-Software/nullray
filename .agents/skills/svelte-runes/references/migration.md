# Migrating to Svelte 5 runes

Use `sv migrate` when upgrading an existing app. Convert file by file if a full
cutover is risky.

## Mechanical replacements

| Svelte 4 | Svelte 5 |
|----------|----------|
| `let x = 0` (component reactive) | `let x = $state(0)` |
| `$: y = x * 2` | `let y = $derived(x * 2)` |
| `$: { sideEffect(x) }` | `$effect(() => { sideEffect(x) })` only if needed |
| `export let name` | `let { name } = $props()` |
| `export let value` + `bind:value` | `$bindable` |
| `<slot name="x">` | `{#snippet x()}` + `{@render x?.()}` |
| `on:click` | `onclick` |
| `createEventDispatcher` | callback props |

## Mode notes

- New components: runes mode
- Legacy features still compile under legacy mode, but do not add new legacy APIs
- `<svelte:options runes={true} />` can force runes in mixed trees when needed

## SvelteKit

- Prefer `$app/state` over `$app/stores`
- Keep request-scoped data out of module-level `$state` singletons
- Use `setContext` / `getContext` for per-request stores created in hooks or
  root layouts

## Validation

1. Run `svelte-check` (and `svelte-check --tsgo` if a TypeScript 7 sidecar exists)
2. Exercise SSR paths that touch shared state
3. Watch for effect loops and for derived logic still living in `$effect`
4. Confirm no new `export let` or `$:` landed in touched files
