# JS and TS format and lint toolchain

## Oxlint and Oxfmt

Oxlint is a native JS/TS linter with large built-in rule coverage (ESLint core,
TypeScript, React, import, unicorn, jest/vitest, a11y, and more). Oxfmt is the
companion formatter.

Migration aids:

- `@oxlint/migrate` from ESLint flat config to `.oxlintrc.json`
- `oxfmt --migrate=prettier` or `--migrate=biome`
- `eslint-plugin-oxlint` to disable overlapping ESLint rules during dual-run

Keep formatting out of the lint pipeline. Drop `eslint-plugin-prettier`.

## Biome

Biome combines formatter and linter. Recommended rules enable by default for
supported languages. Use `biome migrate eslint` when leaving ESLint. Biome's
type-aware story uses its own inference, not the TypeScript compiler, so deep
type-aware rules may still need typescript-eslint or Oxlint type-aware mode.

## ESLint

Still appropriate when the project depends on plugins Oxlint/Biome lack, or
when typescript-eslint type-aware rules are mandatory and already stable on
TypeScript 6. Prefer flat config. Do not add new stylistic rules that fight the
formatter.

## Practical layouts

**Oxlint primary**

```
oxfmt --check
oxlint
tsc --noEmit   # or svelte-check
```

**Biome primary**

```
biome ci
tsc --noEmit
```

**Incremental migration**

```
oxlint
eslint .        # overlapping rules disabled via eslint-plugin-oxlint
```

## Ignores

Always ignore generated output: `dist`, `.svelte-check`, coverage, vendor
bundles. Generated TypeScript wrappers from svelte-check `--tsgo` are a common
source of hundreds of false lint hits.
