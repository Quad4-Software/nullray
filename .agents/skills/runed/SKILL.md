---
name: runed
description: >
  Runed Svelte 5 rune utilities (activeElement, debounced state, observers,
  resource, kit helpers). Use with svelte-runes when composing reactive helpers
  instead of bespoke $effect glue.
---

# Runed

Load with [svelte-runes](../svelte-runes/SKILL.md). Runed is a Svelte 5 utility
library built on runes. npm package `runed` (verified line includes 0.37.x).

```
npm install runed
```

Import into `.svelte` or `.svelte.ts` / `.svelte.js` modules only (needs runes
compiler context).

```svelte
<script lang="ts">
  import { activeElement } from "runed"
  let inputElement = $state<HTMLInputElement | undefined>()
</script>
```

## When to use

| Need | Prefer Runed over |
|------|-------------------|
| DOM/focus observers | Hand-rolled `$effect` + addEventListener |
| Debounced reactive values | Manual timer + state sync |
| Element size / bounds | Repeated ResizeObserver boilerplate |
| Shared typed context | Untyped setContext strings |
| Kit search params helpers | Ad-hoc `page.url` parsing (`runed/kit`) |

Do not replace Svelte primitives. Reach for Runed after a clear repeated
pattern.

Detail: [references/usage.md](references/usage.md).
URLs: [references/urls.md](references/urls.md).

## Footguns

- Nested mutations on some helpers may not be reactive (read docs per utility)
- SSR: prefer utilities that document server behavior
- Keep `$effect` rare. Prefer derived state and Runed helpers that encode it
