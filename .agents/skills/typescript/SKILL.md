---
name: typescript
description: >
  TypeScript 6 vs 7 (native Go compiler / tsgo) adoption, side-by-side
  npm aliases, and tooling breaks with typescript-eslint or svelte-check.
  Use when upgrading TypeScript, adding a fast type-check path, or debugging
  lint and template checkers after a typescript dep change.
---

# TypeScript 6 and 7

Load this skill before changing a TypeScript major, adding a native type-check
script, or chasing typescript-eslint / svelte-check failures after a bump.

## Decision

| Goal | Do this |
|------|---------|
| Keep lint and template checkers working | Keep the `typescript` package name on 6.x API (`@typescript/typescript6`) |
| Fast native `tsc` / editor LSP | Add TypeScript 7 under an alias such as `@typescript/native` |
| One dep and hope | Do not. TypeScript 7.0 ships no stable programmatic API |

TypeScript 6 and 7 share language features. Six is the bridge release that turns
prior deprecations into warnings or removals. Seven hardens those removals and
ships the native Go port (project Corsa / typescript-go).

## Side-by-side layout (recommended)

```json
{
  "devDependencies": {
    "@typescript/native": "npm:typescript@^7.0.2",
    "typescript": "npm:@typescript/typescript6@^6.0.2"
  },
  "scripts": {
    "typecheck": "tsc --noEmit",
    "typecheck:legacy": "tsc6 --noEmit"
  }
}
```

- `typescript` resolves to the 6.x JS API that typescript-eslint and similar tools import
- `@typescript/native` installs TypeScript 7 `tsc` without stealing the package name
- Prefer this over pointing the main dep at 7 while lint still needs the API

Detail: [references/side-by-side.md](references/side-by-side.md).

## Adoption order

1. Move the repo onto TypeScript 6 and clear its hard errors
2. Add the native 7 sidecar and a separate typecheck script
3. Keep JS-engine check as the merge gate until ecosystem tools support 7.1 API
4. For Svelte, prefer `svelte-check --tsgo` only after ignoring `.svelte-check/`

## What breaks on a naive 7 bump

- typescript-eslint (peers still expect typescript below 6.1, and 7.0 has no API)
- Default svelte-check / vue-tsc / Volar template checking
- ts-morph, ts-jest, language-service plugins that import `typescript`

Track typescript-eslint support in issue 10940. Expect real support after a
TypeScript 7.1 API lands and tools adopt it.

Breaking surface and knobs: [references/breaking.md](references/breaking.md).

## Agent workflow

1. Inventory current `typescript` resolution (`npm ls typescript` or equivalent)
2. Land TypeScript 6 and clear hard errors before adding a native 7 sidecar
3. Keep the package name `typescript` on a 6.x API until eslint/svelte tools
   support the 7.1 API
4. Add `@typescript/native` for fast `tsc` / `svelte-check --tsgo`
5. Ignore `.svelte-check/` in git and linters when using `--tsgo`
6. Keep the JS-engine check as the merge gate until the ecosystem catches up

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Announcing TypeScript 7.0: https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/
- Announcing TypeScript 6.0: https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/
- typescript-go (CHANGES.md): https://github.com/microsoft/typescript-go
- typescript-eslint tracking: https://github.com/typescript-eslint/typescript-eslint/issues/10940

