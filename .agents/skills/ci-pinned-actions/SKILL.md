---
name: ci-pinned-actions
description: >
  How to edit GitHub Actions for nullray: SHA pins, harden-runner,
  Dependabot, and immutable releases. Use when changing .github/workflows.
---

# Pinned Actions

## Pin format

```yaml
uses: step-security/harden-runner@e14015d583714f6e62063499dc959a02595150a1 # v2.21.1
```

- Full 40-char commit SHA after @
- Version comment matching the intended tag (# vX.Y.Z)
- Never @v4, @main, or other floating refs

Bump tag comment and SHA in the same commit. Keep the workflow header pin list in sync.

## Harden-Runner first

Every job starts with harden-runner before checkout or installs. Reuse the SHA already in ci.yml / release.yml / dependency-review.yml / codeql.yml unless intentionally bumping.

## Triggers and privileges

- Prefer pull_request and push. Do not add pull_request_target.
- Default permissions: contents: read. Raise only for jobs that must write (release contents: write).
- Do not run untrusted PR shell as a privileged workflow.

## Dependabot

.github/dependabot.yml watches github-actions weekly (limit 5 open PRs). After an actions bump, confirm every uses: line still has SHA plus version comment.

## Releases

release.yml builds on v*.*.* tags. Immutable releases are on. Do not force-move a published tag. Ship a new patch if an artifact is wrong.

docker.yml publishes multi-arch images to GHCR (digest-pinned Dockerfile). Tag releases also build AppImage, Flatpak, and SBOMs attached with a sha256 table in notes.md.

## Checklist

1. harden-runner is step one of each job
2. Every third-party uses: is SHA-pinned with a version comment
3. No floating tags
4. Header pin list updated when versions change
5. No pull_request_target
