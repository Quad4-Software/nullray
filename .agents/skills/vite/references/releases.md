# Vite 8.x release notes (condensed)

## 8.0 (2026-03-12)

- Rolldown as unified bundler (replaces esbuild + Rollup split)
- Optional `resolve.tsconfigPaths`
- Built-in `emitDecoratorMetadata`
- Wasm `?init` in SSR
- `devtools` option
- `server.forwardConsole` for agent-visible client errors
- Breaking: browser target defaults, hot accept URL form removed

## 8.1 (2026-06-23)

- Experimental bundled-dev (`experimental.bundledDev` / `--experimental-bundle`)
- Experimental chunk import map for cache efficiency
- Wasm ESM integration proposal support (`import { fn } from './x.wasm'`)
- Lightning CSS: external CSS imports, plugin file dependency registration
- `import.meta.glob` `caseSensitive` option
- `html.additionalAssetSources`

Toward making Lightning CSS the default CSS transformer in a future major.
Try today with `css.transformer: 'lightningcss'`.

## 8.2 (2026-07-30 line)

- Add `input` to `server.fs.allow`
- Bundled-dev client HMR and reload improvements
- Rolldown-related dependency updates
- Chunk import map CSS chunk mapping fixes (8.2.1)

## 8.3.0 (2026-09-10)

Landed across 8.3.0-beta.0 through stable:

- Top-level `tsconfig` config option
- Accept Rolldown watch options in `server.watch`
- `closeServer` and `closePreviewServer` hooks
- Subpath imports in dynamic `import()` statements
- Preserve search params on workers
- CLI CPU profile naming via `--profile [name]`
- Warn on named imports from JSON modules
- Devtools server integration enablement
- Build preload dependency performance work

Always verify against the live changelog before citing a flag.
