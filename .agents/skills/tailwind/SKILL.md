---
name: tailwind
description: >
  Tailwind CSS v4: Oxide engine, @import "tailwindcss", CSS-first @theme
  config, auto content detection, cascade layers, color-mix, Vite plugin, and
  v3 upgrade. Use when adding or migrating Tailwind, editing theme tokens, or
  choosing between @tailwindcss/vite and PostCSS.
---

# Tailwind CSS v4

Load this skill for Tailwind v4 setup, theme work, or v3 upgrades. Stable v4.0
announced 2025-01-22. Targets Safari 16.4+, Chrome 111+, Firefox 128+.

## Install (Vite preferred)

```
npm install tailwindcss @tailwindcss/vite
```

```js
import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [tailwindcss()],
})
```

```css
@import "tailwindcss";
```

PostCSS path uses `@tailwindcss/postcss` instead. Drop `postcss-import` and
`autoprefixer` for v4 (imports and prefixing are built in).

## Core shifts from v3

| v3 | v4 |
|----|----|
| `@tailwind` directives | `@import "tailwindcss"` |
| `tailwind.config.js` content array | Auto detection (+ `@source` when needed) |
| JS theme config | CSS `@theme { ... }` |
| Separate container-queries plugin | Built-in `@container` / `@max-*` |
| `bg-opacity-*` style utilities | Opacity modifiers (`bg-black/50`) |

Engine is a ground-up rewrite (Oxide). Full builds are much faster. Incremental
rebuilds with no new CSS are measured in microseconds on their benchmarks.

Modern CSS used internally: cascade layers, `@property`, `color-mix()`,
logical properties. Palette tokens move toward OKLCH / P3.

Detail: [references/v4.md](references/v4.md).
Upgrade breaks: [references/upgrade.md](references/upgrade.md).
URLs: [references/urls.md](references/urls.md).

## Theme in CSS

```css
@import "tailwindcss";

@theme {
  --font-display: "Satoshi", "sans-serif";
  --breakpoint-3xl: 1920px;
  --color-avocado-500: oklch(0.84 0.18 117.33);
}
```

Tokens become CSS variables on `:root`. Prefer this over a JS config file.

## Upgrade

```
npx @tailwindcss/upgrade
```

Needs Node 20+. Review the diff. Stick to v3.4 if you must support older
browsers.

## Research URLs

[references/urls.md](references/urls.md).
