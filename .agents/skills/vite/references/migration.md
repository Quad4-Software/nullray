# Vite 7 to 8 migration notes

Source: https://vite.dev/guide/migration (Vite 8 docs).

## Default browser target (NRV)

`build.target` / baseline-widely-available moved to Chrome/Edge 111,
Firefox 114, Safari 16.4 (Baseline Widely Available as of 2026-01-01).

## Rolldown / Oxc replacements

| Old | New |
|-----|-----|
| `optimizeDeps.esbuildOptions` | `optimizeDeps.rolldownOptions` (compat converts, then deprecate) |
| top-level `esbuild` | `oxc` |
| `build.minify: 'esbuild'` | Oxc minify by default (esbuild optional dep if forced) |
| CSS minify | Lightning CSS by default (`build.cssMinify: 'esbuild'` to revert) |
| `build.rollupOptions` | `build.rolldownOptions` |
| `worker.rollupOptions` | `worker.rolldownOptions` |
| object `manualChunks` | removed (function form deprecated, prefer Rolldown `codeSplitting`) |
| `build.rollupOptions.watch.chokidar` | `build.rolldownOptions.watch.watcher` |

`transformWithEsbuild` is deprecated. Prefer `transformWithOxc`. Plugins that
still call esbuild need `esbuild` installed as a direct `devDependency`.

## Behavioral breaks

- Consistent CJS default-import interop. Temporary escape:
  `legacy.inconsistentCjsInterop: true`
- No format-sniffing between `browser` and `module` package fields
- External `require` preserved (not rewritten to `import`)
- `import.meta.url` in UMD/IIFE is `undefined` by default
- `build()` throws `BundleError` with `.errors` array
- `system` and `amd` output formats unsupported
- Passing a URL to `import.meta.hot.accept` removed (pass an id)

## Gradual path

1. Vite 7 + `rolldown-vite` package alias
2. Then Vite 8 and drop the alias

If migrating from `rolldown-vite` only, focus on NRV-labeled sections in the
official guide (non-Rolldown Vite changes).
