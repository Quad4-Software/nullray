---
name: prose
description: >
  Prose and comment style for nullray docs, skills, README, and code comments.
  Catches 2026 AI slop tells (structure, hedging verbs, substance, Markdown
  leakage). Use when writing or editing Markdown, AGENTS notes, comments, or
  commit text.
---

# Prose

Short, concrete, checkable. After each paragraph, name one fact a reader gained (file, flag, number, behaviour). If you cannot, rewrite.

Detail and word lists: [references/tells.md](references/tells.md).

## Hard bans

| Ban | Do instead |
|-----|------------|
| em dash | comma, period, or parentheses |
| emoji / emoji arrows | plain text or ASCII -> |
| semicolon in prose or docs | two sentences or a comma |
| backticks in code comments | bare names |
| Title Case headings | sentence case |
| restating summary closers | end when facts end |
| fake stats with no source | cite, qualify as estimate, or cut the number |

## 2026 priority tells

Em dash alone is a weak forensic signal now. Structure and emptiness dominate. Kill these first:

| Tell | Fix |
|------|-----|
| hedging verbs (ensures, ensuring, highlights, supports, reflects) | say what the thing does |
| X plays a crucial/critical role in shaping Y | name the concrete effect |
| intensifiers with no number (significantly, effectively, increasingly) | cut or attach a measured claim |
| colon runway (The result: / The key insight:) | state the fact |
| synonym triples (fast, reliable, and secure) | one real item, or vary count |
| not X, it is Y (and similar reversals) | one direct claim |
| transition stacking (Furthermore, Moreover, Additionally) | also / and / start the sentence |
| Studies show / Experts agree with no name | cite or own the opinion |
| fabricated precision (47% with no source) | source, estimate label, or delete |
| uniform 15 to 20 word sentences | mix short and long |

## Backticks (docs only)

Reserve for typed tokens: commands, flags, paths, env keys, API ids in tables.

Do not wrap ordinary nouns. Prefer a fenced block for multi-token examples. One inline span per paragraph is enough.

```
WRONG: The `parser` reads `input` and returns a `token` stream.
RIGHT: The parser reads input and returns a token stream.
```

## Changelog

Full rules: [changelog skill](../changelog/SKILL.md). Short user-facing bullets only. No backticks. No harness or test junk.

## Comments

Plain language. No backticks, no Markdown, no TODO noise.

```
// buffer_put clips out of bounds. Wide runes need CELL_WIDE_CONT fillers.
```

## Structure

- Name headings after the content. No thriller titles.
- Prefer tables and fenced blocks over bold-colon bullet lists.
- Cut filler openers (Great question, Importantly, In summary, It is worth noting).
- Hedging only for disputed facts.
- No sycophancy openers or closers.

## Self-check

1. Restatement test passes on every paragraph
2. No em dash, emoji, prose semicolon
3. Comments have no backticks
4. Docs backticks only on typed tokens
5. No hedging-verb padding or role-in-shaping formulas
6. No uncited numbers or floating authority claims
7. Sentence lengths vary. No stacked formal transitions
