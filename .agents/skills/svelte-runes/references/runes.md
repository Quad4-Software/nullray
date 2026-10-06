# Svelte 5 runes reference

Runes are compiler keywords. They are not imported, aliased, or called
conditionally. The `$` prefix is part of the syntax.

## `$state`

```js
let count = $state(0)
let user = $state({ name: 'Ada' })
```

Arrays and plain objects become deeply reactive proxies. Mutations such as
`user.name = ...` or `items.push(...)` trigger updates. The original object is
not mutated when you update proxy properties.

Use `$state.raw(value)` when the value is large and only replaced wholesale
(typical for API responses). Raw state cannot be mutated in place.

`$state.eager(value)` forces earlier UI updates for immediate user feedback.
Use sparingly.

### Classes

Class instances are not proxied as a whole. Declare fields with `$state`, or
assign `$state` as the first write in the constructor.

## `$derived` and `$derived.by`

```js
let doubled = $derived(count * 2)
let total = $derived.by(() => items.reduce((a, b) => a + b.price, 0))
```

`$derived` takes an expression. Use `$derived.by` for multi-statement logic.
Derived object or array results are not made deeply reactive unless you create
`$state` inside `$derived.by`.

## `$effect`

Runs after the DOM updates, tracks reactive reads automatically, and re-runs
when those values change. Browser only.

Prefer alternatives:

| Need | Prefer |
|------|--------|
| Computed value | `$derived` |
| Debug logging | `$inspect` |
| Third-party DOM sync | `{@attach ...}` or an action |
| Event-driven updates | handlers / function bindings |

Avoid writing state inside effects. That pattern recreates the old `$:` sync
bugs as effect cycles.

## `$props` and `$bindable`

```js
let { title, count = $bindable(0), ...rest } = $props()
```

Destructure with defaults. Mark bindable props explicitly. Forward leftover
props with rest instead of `$$restProps`.

## Cross-module state

```ts
// counter.svelte.ts
export const counter = $state({ value: 0 })
```

Reassigning an exported `let` breaks reactivity for importers. Export a stable
object or class and mutate or reassign properties on it.

## Proxies and identity

- `===` against the original object fails after deep `$state`
- Pass proxies into APIs that mutate input carefully
- Prefer reassignment with `$state.raw` for immutable update styles
