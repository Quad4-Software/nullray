---
name: greenfield
description: >
  Bootstrap an empty or nearly empty workspace with scaffolds and a Done
  Contract before edit mode.
---

# Greenfield

Use when the user asks to bootstrap, start a greenfield project, scaffold a new repo, or create a new project layout.

## Flow

1. Call list_dir on the workspace root. If substantial source already exists, stay in plan mode and do not dump packs.
2. Call list_scaffolds. Prefer packs (nullray-workspace, odin-cli) over single files.
3. Write a Done Contract with numbered Steps, a Verify command that matches what the pack ships (for odin-cli use make test after the Makefile exists), Success, and Budget.
4. Stop for approve. Do not switch to edit or call scaffold until the user approves or the harness is in edit mode after --plan-in.
5. In edit mode, call scaffold with the pack name, then implement Steps one at a time.

For GitHub Actions pins, read share/nullray/scaffolds/versions.json and replace placeholders after copying gha-ci.yml. Scaffold does not substitute SHAs.
