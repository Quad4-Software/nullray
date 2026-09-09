---
name: changelog
description: >
  User-facing CHANGELOG style for nullray. Short plain bullets, no backticks,
  no internals. Use when writing or editing CHANGELOG.md, release notes, or
  Unreleased entries.
---

# Changelog

Audience is people who use nullray, not maintainers debugging the harness.

Canon: CHANGELOG.md in the repo root. Match that voice.

## Shape

- Keep a Changelog sections: Added, Changed, Fixed, Removed.
- One short bullet per line. No subordinate clause piles.
- First release lists everything under Added.
- Later releases only ship what users notice.

## Voice

- Plain English. Say what changed for the person running the tool.
- No backticks. No code fences. Bare names for flags, paths, and commands when needed.
- No em dash. No semicolon in prose. No emoji.
- Sentence case headings.

## Keep

- Features someone can try (hunt mode, locate, memory, gate, rename).
- Behaviour fixes (crash gone, local chat works, secrets stay out of output).
- Defaults that change day-to-day use (speculate on, lean print).

## Cut

- Allocator, SIGSEGV free paths, unused returns, build breaks.
- Test-only notes (chat-smoke, package tests, coverage).
- Harness internals (LID envelope fields, projection stubs, metrics gaps).
- Commit-style or file-path dumps unless the path is the user-facing thing.
- Duplicate bullets and restated closers.

## Examples

Wrong:

```
- cites_destroy takes allocator; format_locate_summary used temp_allocator (SIGSEGV)
- Session lock acquire discards both return values from session_try_lock (build break)
- Lean prompts list only lean-core tool names (match tools_json), not the full mode catalog
```

Right:

```
- Locate no longer crashes after returning cites
- Leaner prompts in print mode
- Ephemeral print sessions still keep memory put/delete/forget
```

## Checklist

1. Would a non-contributor care?
2. Can you say it in one short line without backticks?
3. Did you drop allocator, test, and harness junk?
4. Does Unreleased still match CHANGELOG.md tone?
