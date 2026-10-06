# TypeScript 6 bridge and 7 hard errors

Adopt TypeScript 6 first. Its deprecations become hard errors in 7.

## Common removals and defaults

| Area | Change |
|------|--------|
| Defaults | `strict` and `esnext`-oriented defaults in 7 |
| moduleResolution | Legacy `node` / `node10` rejected. Prefer `bundler`, `node16`, or `nodenext` |
| baseUrl | Deprecated path. Prefer explicit `paths` without relying on baseUrl alone |
| Targets | ES5-era targets and AMD/UMD emit paths are gone or rejected |
| Features | No new language syntax in 7.0. Feature work resumes on 7.x after the port |

Exact diffs live in typescript-go `CHANGES.md`.

## Tool matrix (as of TypeScript 7.0.x)

| Tool | Can use 7.0 as sole `typescript`? |
|------|-----------------------------------|
| `tsc` / native LSP | Yes |
| typescript-eslint type-aware rules | No (blocked on API) |
| svelte-check default mode | No |
| svelte-check `--tsgo` | Yes with native package present |
| vue-tsc / Volar default | No |
| ts-morph | No (risk of wrong output) |
| ts-jest / ts-patch transformers | No |

## Editor

TypeScript 7 uses an LSP-based language server, not classic `tsserver` from the
7 package. VS Code has a dedicated TypeScript Native extension. Other editors
consume the LSP server. Follow each editor's docs when switching.

## Nightlies

Historical preview package: `@typescript/native-preview`. Stable installs use
the `typescript` package. Nightlies move back under `typescript@next`.

## Verify after a bump

1. `npm ls typescript` (or pnpm / yarn equivalent) and confirm aliases
2. Run the JS-API gate (eslint type-aware or svelte-check without `--tsgo`)
3. Run native `tsc --noEmit` or `svelte-check --tsgo`
4. Confirm generated caches are ignored
5. Compare diagnostic counts. Investigate drift before dropping the JS gate
