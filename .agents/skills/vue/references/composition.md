# Composition API norms

Official FAQ: https://vuejs.org/guide/extras/composition-api-faq.html

## What it covers

- Reactivity: `ref`, `reactive`, `computed`, watchers
- Lifecycle hooks as imports (`onMounted`, …)
- `provide` / `inject`

Composition API is not functional programming. It uses Vue mutable fine-grained
reactivity.

## Why prefer it for new code

- Logic reuse via composables beats mixins
- Related logic can sit together instead of splitting across Options buckets
- Type inference is natural for variables and functions
- `<script setup>` templates compile against local bindings (better minify)

## Still valid Options API

Vue has no plan to deprecate Options API for VDOM. Mixing via `setup()` inside
an Options component is for bridging old codebases, not a default for new SFCs.

## Practical defaults

1. One concern per composable file when reuse or size demands it
2. Prefer `computed` over watchers that only derive values
3. Prefer template refs and declarative bindings over manual DOM work
4. Keep Options-only APIs (`name`, `inheritAttrs`) via `defineOptions` when
   needed (3.3+)
5. For TS, Composition API avoids Options inference gymnastics

## Bundle note

A compile-time flag can drop Options API runtime if the whole graph (including
dependencies) never needs it.
