# Migrating HTMX 2 to 4

## Three user-visible changes

1. Inheritance: parents no longer implicitly pass attrs. Use `:inherited`
   or set `htmx.config.implicitInheritance = true` temporarily
2. Events: rename listeners to the standardized pattern. `htmx:xhr:*` goes
   away with Fetch
3. History: no DOM snapshot cache by default. Use `hx-history-cache` if you
   need local cache behavior

## Error swaps

4.x swaps 400/500 HTML by default. To restore 2.x non-swap for errors:

```js
htmx.config.noSwap = [204, 304, '4xx', '5xx']
```

Default retains 204 and 304 as no-swap.

## Compat shim

`htmx-2-compat` maps old event names, implicit inheritance, and related 2.x
behaviors onto 4 for gradual migration.

Docs: https://four.htmx.org/extensions/htmx-2-compat

## Morph

Prefer built-in morph swaps over the old Idiomorph-only extension path.

## Support policy

HTMX 2 remains supported indefinitely. Upgrade when Fetch streaming, morph, or
cleaner defaults matter. No forced deadline from the project.
