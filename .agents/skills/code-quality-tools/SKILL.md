---
name: code-quality-tools
description: >
  Formatting, linting, and SAST tool choices (Biome, Oxlint, ESLint, Prettier,
  Semgrep, CodeQL, language-native analyzers). Use when adding CI quality gates,
  migrating linters, or separating style checks from security scanning.
---

# Formatting, linting, and SAST

Load this skill when wiring quality gates, migrating formatters or linters, or
deciding which scanner belongs in PR vs nightly CI.

## Agent workflow

1. Separate format, lint, typecheck, SAST, and SCA into distinct CI steps
2. Pick one formatter and one primary linter for JS/TS. Avoid triple stacks
3. Put fast SAST (Semgrep) on PRs. Schedule heavier CodeQL when needed
4. Fail closed on triaged high findings. Document suppressions
5. For this repo, keep `make test` as the primary gate. Add scanners for scripts/web/workflows when hunting

## Layers (keep separate)

| Layer | Job | Examples |
|-------|-----|----------|
| Format | Deterministic style, no semantic debate | Oxfmt, Prettier, Biome format, gofmt, odinfmt |
| Lint | Bug-prone patterns and API misuse | Oxlint, ESLint, Biome lint, clippy, golangci-lint |
| Typecheck | Types and API contracts | `tsc`, `svelte-check`, `go test` type errors |
| SAST | Security vulnerabilities and taint | Semgrep, CodeQL, language security analyzers |
| SCA | Dependency advisories | osv-scanner, npm audit, Dependabot |

Do not treat eslint-plugin-security as a full SAST program. Do not run format
rules inside the linter when a dedicated formatter exists.

## JavaScript / TypeScript defaults

Pick one formatter and one primary linter. Avoid triple stacks.

| Need | Prefer |
|------|--------|
| Fast lint + broad ESLint-like rules | Oxlint (migrate with `@oxlint/migrate`) |
| All-in-one format+lint | Biome |
| Niche plugins still required | ESLint flat config, optionally beside Oxlint with overlapping rules disabled |
| Format only | Oxfmt or Prettier, run as its own CI step |

TypeScript 6/7 tooling notes live in [typescript](../typescript/SKILL.md).

Detail: [references/js-toolchain.md](references/js-toolchain.md).
SAST placement: [references/sast.md](references/sast.md).

## CI shape

1. Format check (fail on drift)
2. Lint
3. Typecheck
4. Unit / package tests
5. SAST on every PR when fast (Semgrep). Deeper CodeQL on schedule or main
6. SCA / advisory scan

Fail closed on high SAST findings the team has triaged as real. Suppress with
documented justifications, not silent ignores.

## nullray / polyglot

Match the language's standard tools. For this repo, Odin tests and structure
checks are the primary gate (`make test`). Add Semgrep or similar when hunting
cross-language issues in scripts, web, or workflows.

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Oxlint: https://oxc.rs/docs/guide/usage/linter.html
- Biome: https://biomejs.dev/guides/getting-started/
- Semgrep: https://semgrep.dev/docs/
- CodeQL: https://codeql.github.com/docs/

