# Vue 3.6 Vapor Mode (RC)

Sources: vuejs/core `v3.6.0-rc.1` notes and `minor` CHANGELOG.

## Status

3.6 entered RC when Vapor feature work completed. Reactivity package moved onto
alien-signals. As of Sep 2026 pre-releases continue (`rc.8` observed). Do not
treat Vapor as production-stable until 3.6 final.

Recommended RC uses: one performance-sensitive page, or a small all-Vapor app.

## Opt-in

```vue
<script setup vapor>
</script>

<script vapor>
</script>

<template vapor>
</template>
```

## App entry

```js
import { createVaporApp } from 'vue'
createVaporApp(App).mount('#app')
```

```js
import { createApp, vaporInteropPlugin } from 'vue'
createApp(App).use(vaporInteropPlugin).mount('#app')
```

Keep Vapor and VDOM regions separate when possible. Interop covers common
props, events, and slots, not every library edge case. JSX / render-function
components stay VDOM and need interop inside a Vapor tree.

## Unsupported / different

- Options API
- `app.config.globalProperties`
- `getCurrentInstance()` returns `null` in Vapor components
- `@vue:xxx` per-element lifecycle events
- `v-memo`
- Template refs without `$el` / `$props` / `$attrs` / `$slots` / `$refs`

Custom directives use a different signature (`value` as a reactive getter,
optional cleanup return).

`slots.default()` is not a safe dry-run. Calling it may create DOM and effects.
Leave slot rendering to the template.

## Event delegation change

Early docs: eligible events delegated to `document` by default, which broke
cases where an ancestor called `stopPropagation()`.

Later RC CHANGELOG (`make event delegation opt-in`, #15127): attach listeners
directly by default. Opt into document delegation with the Vapor-only
`.delegate` modifier:

```vue
<button @click.delegate="onClick" />
```

`compilerOptions.eventDelegation` was removed.
