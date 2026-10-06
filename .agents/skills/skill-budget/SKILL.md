---
name: skill-budget
description: >
  How nullray skills use context: catalog vs load_skill, caps, and when not to
  preload. Use when tuning prompts, adding skills, or diagnosing token bloat.
---

# Skill budget

Load this when optimizing agent context or authoring skills.

## How loading works

| Layer | What enters context | Cost |
|-------|---------------------|------|
| Catalog | id + description for every discovered skill | Scales with skill count |
| `load_skill` / auto-match | Full SKILL.md body (refs not auto-inlined) | Pay per loaded skill |
| References | Only if the model reads those files | On demand |

Caps in `nullray/skills/skills.odin`:

- `MAX_SKILLS` 96
- `MAX_SKILL_BYTES` 24000 per body (trimmed if larger)
- `MAX_ACTIVE_SKILLS` 3 auto-matched into a turn

Bodies are **not** preloaded into the system prefix. Catalog text reminds the
model to call `load_skill`.

## Authoring for low tokens

1. Keep SKILL.md short (tables + steps). Put depth in `references/`
2. Keep descriptions specific but under ~600 chars when possible
3. Always add `references/urls.md` for curl/fetch instead of pasting docs
4. Prefer one focused skill over mega-skills
5. Link siblings instead of duplicating

## Agent behavior

- `list_skills` when unsure which id matches
- `load_skill` only for skills that change the current task
- Read `references/*.md` only when SKILL.md points there
- Do not paste entire catalogs into user replies

Measured ballpark (workspace skills, rough 4 chars/token, Sep 2026): about 52
workspace skills, catalog descriptions ~10k chars (~2.5k tokens). All bodies
together ~96k chars (~24k tokens) if wrongly preloaded. Auto-match caps at 3.
Worst three large bodies alone ~11k chars (~2.8k tokens). Prefer `--bare` when
you only want workspace skills (skips home MCP and `~/.agents` skills).

URLs: [references/urls.md](references/urls.md).
