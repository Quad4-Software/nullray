---
name: scaffold
description: >
  Start security-sensitive files from repository templates and update pinned
  versions without introducing floating dependencies.
---

# Scaffold

Templates live under `share/nullray/scaffolds/`. Read `versions.json` before replacing placeholders.

## GitHub Actions

Start from `gha-ci.yml`. Replace every `__..._SHA__` token with the matching 40-character commit from `versions.json`. Keep the version comment beside each pin.

Keep harden-runner as the first step in every job. Keep default permissions read-only. Do not add `pull_request_target`.

After copying a template, adapt names and build steps to the project. Run the relevant parser, linter, and tests. A scaffold is a starting point, not a security review.
