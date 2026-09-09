---
name: scaffold
description: >
  Start security-sensitive files from repository templates and update pinned
  versions without introducing floating dependencies. List templates with
  list_scaffolds. Multi-file packs use MANIFEST.txt under packs/.
---

# Scaffold

Templates live under `share/nullray/scaffolds/`. Read `versions.json` before replacing placeholders.

Call list_scaffolds (read-only, plan mode safe) to see file templates and packs. Use scaffold with a name to copy one file or a whole pack.

## Packs

Packs live under `share/nullray/scaffolds/packs/<name>/` with `MANIFEST.txt` (one relative dest path per line). Scaffold copies every listed file. Refuse overwrite unless force=true (all-or-nothing).

Shipped packs: nullray-workspace, odin-cli.

## GitHub Actions

Start from `gha-ci.yml`. Replace every `__..._SHA__` token with the matching 40-character commit from `versions.json`. Keep the version comment beside each pin.

Keep harden-runner as the first step in every job. Keep default permissions read-only. Do not add `pull_request_target`.

After copying a template, adapt names and build steps to the project. Run the relevant parser, linter, and tests. A scaffold is a starting point, not a security review.
