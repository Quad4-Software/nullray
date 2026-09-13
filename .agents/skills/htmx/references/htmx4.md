# HTMX 4 details

Sources: four.htmx.org announcement (2026-08-28), docs migration section,
htmx-2-compat page, The fetch()ening essay.

## npm tags

4.0 is not marked `latest` on purpose. Unversioned CDN URLs keep getting 2.x.
Website and four.htmx.org document 4. Plan for `latest` to move in early 2027.

## Explicit inheritance

Suffix attributes with `:inherited` so children pick them up. Child values
override by default. `:append` merges with an inherited value. Old
`hx-disinherit` style controls are obsolete.

## Event rename pattern

Form: `htmx:phase:action[:sub-action]`

Examples:

| HTMX 2 | HTMX 4 |
|--------|--------|
| `htmx:beforeRequest` | `htmx:before:request` |
| `htmx:afterRequest` | `htmx:after:request` |
| `htmx:beforeSwap` | `htmx:before:swap` |
| `htmx:afterSwap` | `htmx:after:swap` |
| `htmx:configRequest` | `htmx:config:request` |

Most errors collapse to `htmx:error`. HTTP error responses fire
`htmx:response:error`. `htmx:xhr:*` and `htmx:validation:*` go away with fetch
and native form validation.

## History

No default `localStorage` DOM snapshots. Back navigation re-fetches and swaps
into `body` or `[hx-history-elt]`. Optional `hx-history-cache` extension uses
`sessionStorage` and aims to play better with Alpine-style scripting.

## Morph and partials

Morphing swaps ship in core (improved idiomorph work). `<partial>` templates
carry normal `hx-target` / `hx-swap` for multi-target updates. Out-of-band swaps
narrow back toward simple id replacement.

## HTTP swap defaults

Default `htmx.config.noSwap` is `[204, 304]`. Unlike 2.x, 4xx and 5xx responses
swap unless configured otherwise.

## Compat

`htmx-2-compat` restores 2.x event names, implicit inheritance, `hx-ext`
activation patterns, and related behaviors for gradual upgrades.

## Extensions worth knowing

- `hx-preload`, `hx-download`, `hx-alpine-compat`, `hx-history-cache`
- Streaming: `hx-sse`, `hx-ws`, `hx-multipart`
- `hx-live` scripting companion
- `htmax.js` bundle packages popular extensions together
