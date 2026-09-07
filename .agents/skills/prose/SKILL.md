---
name: prose
description: >
  Prose and comment style for nullray docs, skills, README, and code comments.
  Use when writing or editing Markdown, AGENTS notes, comments, or commit text.
---

# Prose

Short, concrete, checkable. Every sentence should land on a file, flag, number, or behaviour.

## Hard bans

| Ban | Do instead |
|-----|------------|
| em dash | comma, period, or parentheses |
| emoji | plain text |
| emoji arrows | ASCII `->` |
| semicolon in prose or docs | two sentences or a comma |
| backticks in code comments | bare names |
| Title Case headings | sentence case |
| restating summary closers | end when facts end |

## Backticks (docs only)

Use for things a reader types or pastes: commands, flags, paths, env keys, API ids in tables.

Do not wrap ordinary nouns (the parser, the buffer, the session). One inline span per paragraph is enough. Prefer a fenced codeblock for multi-token examples.

```
WRONG: The `parser` reads `input` and returns a `token` stream.
RIGHT: The parser reads input and returns a token stream.
```

## Comments

Plain language. No backticks, no Markdown, no TODO noise.

```
// buffer_put clips out of bounds. Wide runes need CELL_WIDE_CONT fillers.
```

## Structure

- Name headings after the content. No thriller titles.
- Prefer tables and fenced blocks over bold-colon bullet lists.
- Vary sentence length. Cut filler openers (Great question, Importantly, In summary).
- Ban synonym triples (fast, reliable, and secure) unless each item is distinct and real.
- Hedging only for disputed facts. Established behaviour needs none.

## Self-check

1. No em dash character
2. No emoji
3. No semicolon in prose or docs
4. Comments have no backticks
5. Docs backticks only on typed tokens
6. Every claim checkable
7. No sycophancy openers or closers

Longer rule pack lives outside this repo if needed. This skill is the project minimum.
