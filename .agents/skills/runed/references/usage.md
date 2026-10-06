# Runed usage notes

## Import paths

- Core: `import { ... } from "runed"`
- SvelteKit helpers: `import { ... } from "runed/kit"` when documented

## Patterns

Many helpers expose a `.current` field read inside templates or `$effect`.

Prefer documenting which utility you chose in PRs so reviewers can check the
official page for SSR and reactivity scope.

## Pairing

- Reactivity rules: [svelte-runes](../../svelte-runes/SKILL.md)
- Components: official Svelte docs via MCP when available
