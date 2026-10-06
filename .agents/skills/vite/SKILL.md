---
name: vite
description: >
  Vite 8 through 8.3.x: Rolldown unification, migration from Vite 7,
  experimental bundled-dev, chunk import maps, Wasm ESM, Lightning CSS
  progress, and server.forwardConsole for coding agents. Use when upgrading
  Vite, configuring builds, enabling agent console forwarding, or debugging
  Rolldown/Oxc migration breaks.
---

# Vite 8 through 8.3

Load this skill for Vite 8.x upgrades and config. Stable 8.0 shipped
2026-03-12. Line continues through 8.3.0 (2026-09-10). Always re-check the
live migration guide and changelog before citing a flag.

## Architecture

Vite 8 replaces dual esbuild (dev) + Rollup (prod) with one Rust bundler,
Rolldown, plus Oxc for JS transform and minify. Most Rollup-compatible Vite
plugins keep working. CSS minify defaults to Lightning CSS.

Node: 20.19+ or 22.12+ (same as Vite 7).

## Version map

| Version | Focus |
|---------|-------|
| 8.0 | Rolldown merge, browser target bump, Devtools option, `resolve.tsconfigPaths`, `emitDecoratorMetadata`, Wasm SSR `?init`, `server.forwardConsole` |
| 8.1 | Experimental bundled-dev, chunk import maps, Wasm ESM imports, Lightning CSS gaps filled, `html.additionalAssetSources` |
| 8.2 | `input` on `server.fs.allow`, bundled-dev HMR hardening, Rolldown bumps |
| 8.3 | Top-level `tsconfig`, `server.watch` Rolldown options, `closeServer` / `closePreviewServer`, subpath dynamic imports, `--profile [name]`, JSON named-import warnings |

Detail: [references/releases.md](references/releases.md).
Migration breaks: [references/migration.md](references/migration.md).
URLs: [references/urls.md](references/urls.md).

## Agent-relevant knobs

- `server.forwardConsole`: browser console and unhandled errors to the terminal.
  Default auto-on when a coding agent is detected (`@vercel/detect-agent`)
- `experimental.bundledDev: true` or CLI `--experimental-bundle` for huge graphs
- Compat layer still maps many `esbuild` / `rollupOptions` keys. Prefer
  `oxc` and `rolldownOptions` / `optimizeDeps.rolldownOptions`

## Upgrade path

1. Read https://vite.dev/guide/migration
2. Optional: try `rolldown-vite` on Vite 7 first to isolate bundler issues
3. Pin `vite` to a current 8.x patch
4. Run build and dev. Fix plugin and CJS interop breaks
5. Turn on `forwardConsole` when agents drive the browser

## Research URLs

Fetch before inventing options: [references/urls.md](references/urls.md).
