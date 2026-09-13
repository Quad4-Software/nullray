---
name: htmx
description: >
  HTMX 2 vs HTMX 4 (released 2026-08-28): fetch() core, explicit :inherited
  attributes, renamed events, history re-fetch, built-in morph swaps, 4xx/5xx
  swap default change, htmx-2-compat, and npm latest vs next tags. Use when
  writing or upgrading htmx apps, choosing CDN tags, or debugging inheritance.
---

# HTMX 2 and HTMX 4

Load this skill for htmx work. HTMX 4.0.0 released 2026-08-28. HTMX 2 remains
supported indefinitely. On npm, `latest` stays on 2.x and `next` tracks 4.x
until early 2027-ish so unpinned CDNs do not force-upgrade.

## Install reality

| Channel | Version |
|---------|---------|
| npm `latest` / many CDNs without a version | 2.x |
| npm `next` or exact `4.0.0` | 4.x |
| Site docs | four.htmx.org is the 4 docs surface |

Pin an exact version in production.

## What changed in 4 (user-visible)

| Area | HTMX 2 | HTMX 4 |
|------|--------|--------|
| Transport | `XMLHttpRequest` | `fetch()` |
| Inheritance | Implicit by default | Explicit `:inherited` |
| Events | Organic names (`htmx:afterSwap`) | `htmx:phase:action[:sub]` |
| History | `localStorage` snapshots | Re-fetch and swap (cache is an extension) |
| Morph | Extension | Built-in morph swaps |
| Error HTTP | Often no swap on 4xx/5xx | Swaps by default (only 204/304 in `noSwap`) |

Internals essay: The fetch()ening. Detail: [references/htmx4.md](references/htmx4.md).
Migration checklist: [references/migrate-4.md](references/migrate-4.md).
URLs: [references/urls.md](references/urls.md).

## Inheritance example

```html
<div hx-target:inherited="#out" hx-confirm:inherited="Sure?">
  <button hx-delete="/item/1">Delete</button>
</div>
```

Restore 2.x implicit inheritance with `htmx.config.implicitInheritance = true`
or load the `htmx-2-compat` extension.

## Upgrade helpers

```
npx htmx.org@4.0.0 upgrade-check -- ./templates
```

Compat extension maps old event names, implicit inheritance, and related 2.x
behaviors. Prefer a real migration for long-lived apps.

Restore 2.x no-swap on errors:

```js
htmx.config.noSwap = [204, 304, '4xx', '5xx']
```

## Research URLs

[references/urls.md](references/urls.md).
