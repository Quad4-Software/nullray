---
name: vue
description: >
  Vue 3 Composition API norms plus Vue 3.6 RC Vapor Mode: opt-in vapor SFCs,
  alien-signals reactivity, createVaporApp, vaporInteropPlugin, unsupported
  APIs, and .delegate event opt-in. Use when writing Vue 3 SFCs, migrating to
  script setup, or evaluating Vapor Mode on 3.6 RC.
---

# Vue 3 Composition API and Vapor

Load this skill for Vue 3 component work and for 3.6 Vapor Mode experiments.
Stable line for production remains 3.5.x until 3.6 ships. As of Sep 2026,
3.6 is still RC (through at least `v3.6.0-rc.8`).

## Composition API norms

Prefer `<script setup>` for new components.

| Concern | Prefer |
|---------|--------|
| State | `ref` / `reactive` / `shallowRef` |
| Derived | `computed` |
| Side effects | `watch` / `watchEffect` with explicit stop or scope |
| Lifecycle | `onMounted`, `onUnmounted`, and friends |
| Reuse | composable functions (`useX`), not mixins |
| Props / emits | `defineProps` / `defineEmits` (and `defineModel` when two-way) |

`setup()` runs once. No React Hooks call-order rules. Options API stays
supported for VDOM apps. Vapor Mode does not support Options API.

Detail: [references/composition.md](references/composition.md).

## Vapor Mode (3.6 RC)

Opt-in compile mode that drops VNode overhead for a supported API subset.
Feature-complete in RC. Use for hot pages or small pure-Vapor apps first.

```vue
<script setup vapor>
// ...
</script>
```

Also valid: `<script vapor>`, or `<template vapor>` for the whole SFC.

| Goal | API |
|------|-----|
| Pure Vapor app | `createVaporApp(App)` |
| Vapor inside `createApp` | `.use(vaporInteropPlugin)` |
| VDOM inside Vapor app | same plugin (pulls VDOM runtime) |

Unsupported or different in Vapor: Options API, `globalProperties`,
`getCurrentInstance()` (null), `@vue:xxx` element hooks, `v-memo`, and
instance proxy fields on template refs (`$el`, `$props`, …).

Reactivity core in 3.6 is refactored onto alien-signals.

### Event delegation (later RCs)

Early RC notes described document-level delegation by default. Later changelog
made delegation opt-in via `@click.delegate` (and peers). Direct listeners are
the default again. Remove obsolete `compilerOptions.eventDelegation`.

Detail: [references/vapor.md](references/vapor.md).
URLs: [references/urls.md](references/urls.md).

## Research URLs

[references/urls.md](references/urls.md).
