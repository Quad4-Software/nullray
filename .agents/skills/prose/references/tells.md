# Prose tells (2026)

Companion to the prose skill. Patterns that mark low-substance or machine-shaped text. Convergence matters. One hit is noise. Several in a short passage is a rewrite.

Sources informing this list: Kobak et al. PubMed style-word spike, Antislop / Dekoninck-style overuse ratios, SlopDetector measurable thresholds (2026), structural hedging-verb studies, Wikipedia Signs of AI Writing themes. Prefer substance over authorship guesses.

## Substance first

| Test | Fail | Pass |
|------|------|------|
| Restate | fluent but no nameable fact | one file, flag, number, or behaviour |
| Delete | paragraph vanishes with no loss | removing it drops a real detail |

Hollow confident prose is the strongest 2026 tell. Punctuation cleanup alone does not fix it.

## Vocabulary

| Avoid | Prefer |
|-------|--------|
| delve, tapestry, underscore, showcase, unveil | explore, show, stress, introduce |
| utilize, leverage, facilitate, harness | use, help, apply |
| robust, seamless, groundbreaking, transformative, cutting-edge | solid, smooth, new (only if true) |
| unlock, empower, elevate, streamline | open, allow, raise, simplify |
| ensuring / ensures / highlights / supports / reflects as padding | concrete verb for the actual action |
| significantly / effectively / increasingly with no measure | cut, or attach a number |

Style-word clusters after late 2022 (delve-class) remain useful when denser than about 3 flagged words per 500 words. Single hits are weak.

## Formula sentences

```
WRONG: X plays a crucial role in shaping Y.
RIGHT: X sets Y by <specific mechanism>.

WRONG: The result: generic content fails.
RIGHT: Generic content fails.

WRONG: It is not just about speed. It is about reliability.
RIGHT: Speed without retries still drops messages.

WRONG: Nutrition plays a crucial role in overall wellness.
RIGHT: Swap the 6 p.m. soda for water and cut about 40,000 calories a year.
```

Colon runways rose as models avoided em dashes. Same dramatic-pause job. State the fact.

## Structure and rhythm

| Pattern | Threshold / rule |
|---------|------------------|
| Rule of three | more than one polished triplet per ~200 words is autopilot |
| Burstiness | stdev/mean of sentence word-counts under ~0.4 is metronome prose |
| Transition stacking | more than half of paragraphs opening with Furthermore/Moreover/Additionally/Consequently/Ultimately |
| Paragraph uniformity | many same-length paragraphs in a row |
| Opening-word repetition | three+ consecutive paragraphs with the same opener |
| Em dash density | project ban is zero. Forensic signal alone is weak below ~20 per 1000 words |

Technical docs can be legitimately uniform. Still vary sentence length when explaining behaviour.

## Authority and numbers

```
WRONG: Studies show that quality matters.
RIGHT: BCG 2025 study of 1,250 firms found only 5% achieve AI value at scale.
  or: In this codebase, quality means make test stays green.

WRONG: Teams see a 47% improvement.
RIGHT: cite method, mark as estimate, or drop the number.
```

Uncited precision reads as hallucination. Repeat the same lonely statistic as wallpaper is another tell. Use it once with context.

## Markdown leakage

Chat formatting bleeding into docs:

- bold-term-colon bullet lists for every item
- mechanical bold on key terms
- Title Case On Every Heading
- curly quotes
- backtick inflation on ordinary nouns
- emoji section markers and decorative arrows (use ->)

Comments: no backticks, no Markdown, no TODO filler.

## Voice and chat leftovers

| Cut | Why |
|-----|-----|
| Great question / Happy to help / Hope this helps | sycophancy |
| Importantly / Notably / In summary / At its core | throat-clearing |
| In today's fast-paced world / In an era of | empty openers |
| Unlock the secrets / Master the art | guru pitch |
| Research suggests / Experts agree (unnamed) | fake authority |
| It depends / both have merits with no deciding factor | fake neutrality |

## Project hard rules (nullray)

Already enforced in the prose skill:

- no em dashes
- no emojis
- no emoji arrows (ASCII -> only)
- no semicolons in prose or docs
- no backticks inside code comments
- prefer tables and fenced blocks over chat-shaped lists

## Quick pass order

1. Substance / restatement
2. Hedging verbs and role-in-shaping formulas
3. Uncited numbers and floating authority
4. Triples, contrast tics, colon runways
5. Transition stacking and sentence-length sameness
6. Style words and corporate verb inflation
7. Markdown leakage and project punctuation bans
