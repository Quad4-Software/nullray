# Side-by-side TypeScript 6 and 7

## Why two packages

TypeScript 7.0 is a faithful native port. Same checking semantics, native speed,
shared-memory parallelism. It does not ship a stable embeddable compiler API.
Microsoft expects a new API in 7.1. Until tools rewrite against that API, keep
6.x available under the name `typescript`.

`@typescript/typescript6` provides:

- `tsc6` binary
- Re-export of the TypeScript 6.0 JS API

## Alias recipes

Native as primary `tsc`, 6 for API consumers (Microsoft blog shape):

```json
{
  "devDependencies": {
    "@typescript/native": "npm:typescript@^7.0.2",
    "typescript": "npm:@typescript/typescript6@^6.0.2"
  }
}
```

JS toolchain as gate, native as optional fast path (common in Svelte repos):

```json
{
  "devDependencies": {
    "@typescript/native": "npm:typescript@^7.0.2",
    "typescript": "^6.0.3"
  },
  "scripts": {
    "check": "svelte-check --tsconfig ./tsconfig.json",
    "check:tsgo": "svelte-check --tsgo --tsconfig ./tsconfig.json"
  }
}
```

svelte-check discovers `@typescript/native` or `@typescript/native-preview` and
requires the resolved package to be typescript >= 7.

## Svelte trap: `.svelte-check/`

`svelte-check --tsgo` writes generated `++*.svelte.ts` wrappers under
`.svelte-check/`. Put that directory in `.gitignore` and in the linter ignore
list. Otherwise `eslint .` or oxlint walks generated files and reports hundreds
of false errors.

## Parallelism knobs (TypeScript 7)

| Flag | Role |
|------|------|
| `--checkers N` | Type-checker workers (default 4) |
| `--builders N` | Project-reference build workers under `--build` |
| `--singleThreaded` | Disable parallelization for debug or tiny CI hosts |

Raising `--checkers` and `--builders` together multiplies memory. Pin values in
CI if order-dependent diagnostics appear across machines.

## Authority

Until 7.1 ecosystem support is real:

- Keep the JS engine check as the authoritative CI gate
- Treat native check as a fast second opinion
- Fix implicit-any findings that tsgo surfaces for snippet and callback params
  (annotate params so both engines agree)
