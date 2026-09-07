---
name: ci-pinned-actions
description: >
  How to edit GitHub Actions for nullray: SHA pins, harden-runner,
  Dependabot, and immutable releases. Use when changing .github/workflows.
---

# Pinned Actions and CI security

## Pin every third-party action

Format:

```yaml
uses: step-security/harden-runner@e14015d583714f6e62063499dc959a02595150a1 # v2.21.1
```

Requirements:

- Full 40-character commit SHA after `@`
- Version comment matching the tag you intend (`# vX.Y.Z`)
- Never `@v4`, `@main`, or other floating refs

When Dependabot or a manual bump lands, change the tag comment and the SHA in the same commit. Keep the pin list in the workflow header comment in sync.

## Harden-Runner first

Every job starts with harden-runner before checkout or installs. Current pin lives in `ci.yml`, `release.yml`, `dependency-review.yml`, and `codeql.yml`. Reuse that SHA unless you are intentionally bumping.

## Triggers and privileges

- Prefer `pull_request` and `push`. Do not add `pull_request_target`.
- Default `permissions: contents: read`. Raise only for jobs that must write (release contents: write).
- Do not run untrusted PR shell as a privileged workflow.

## Dependabot

`.github/dependabot.yml` watches `github-actions` weekly (limit 5 open PRs). After merging an actions bump, confirm every `uses:` line still has a SHA plus version comment.

## Releases

`release.yml` builds on `v*.*.*` tags. Immutable releases are on. Do not force-move a published tag. Ship a new patch version if an artifact is wrong.

## Checklist for a workflow edit

1. harden-runner is step one of each job
2. Every third-party `uses:` is SHA-pinned with a version comment
3. No floating tags
4. Header pin list updated when versions change
5. No `pull_request_target`
