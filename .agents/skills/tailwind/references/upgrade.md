# Tailwind v3 to v4 upgrade

Source: https://tailwindcss.com/docs/upgrade-guide

## Tooling

```
npx @tailwindcss/upgrade
```

Migrates dependencies, CSS entry, and many template class renames. Node 20+.

Vite projects should prefer `@tailwindcss/vite` over the PostCSS plugin.
CLI moves to `@tailwindcss/cli`.

## Import change

```css
/* v3 */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* v4 */
@import "tailwindcss";
```

## Removed deprecated utilities

| Deprecated | Replacement |
|------------|-------------|
| `bg-opacity-*` (and text/border/divide/ring/placeholder) | Opacity modifiers (`bg-black/50`) |
| `flex-shrink-*` / `flex-grow-*` | `shrink-*` / `grow-*` |
| `overflow-ellipsis` | `text-ellipsis` |
| `decoration-slice` / `decoration-clone` | `box-decoration-slice` / `box-decoration-clone` |

## Renamed scales (partial)

| v3 | v4 |
|----|----|
| `shadow-sm` | `shadow-xs` |
| `shadow` | `shadow-sm` |
| `blur-sm` / `rounded-sm` / `drop-shadow-sm` | matching `*-xs` |
| bare `blur` / `rounded` / `drop-shadow` | matching `*-sm` |
| `outline-none` | `outline-hidden` (true `outline-none` is new) |
| `ring` (was 3px) | `ring-3` (bare `ring` is 1px in v4) |
| `bg-gradient-*` | `bg-linear-*` |

## Selector changes

`space-*` and `divide-*` selectors changed for performance. Prefer flex/grid
`gap` if layout shifts. Gradient variant overrides no longer reset the whole
gradient. Use `via-none` when clearing a middle stop.

## Browser floor

v4 needs modern CSS (`@property`, `color-mix()`). Stay on v3.4 for older
browsers.
