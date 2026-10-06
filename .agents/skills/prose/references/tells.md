# Prose tells (2026)

Companion to the prose skill. Patterns that mark low-substance or machine-shaped text. Convergence matters. One hit is noise. Several in a short passage is a rewrite.

Sources informing this list: Kobak et al. PubMed style-word spike, Antislop / Dekoninck-style overuse ratios, SlopDetector measurable thresholds (2026), structural hedging-verb studies, Wikipedia Signs of AI Writing themes, Opace dual-corpus measurement across 21 models (Aug 2026), humzakt/ai-writing-markers dataset. Prefer substance over authorship guesses.

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
| serves as / functions as / features / boasts for is / has | is, has, includes |
| whether you are / here is the thing / paving the way in docs | cut, chat register leakage |

Style-word clusters remain useful when denser than about 3 flagged words per 500 words. Single hits are weak. On 2026 models delve itself measures 0.2x, a human-leaning signal. Cut it as inflation, not as authorship evidence.

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
| Sentence rhythm | CV of sentence lengths at or under ~0.3 measured 3.6x AI. Solo burstiness is weak (AUROC ~0.52), pair with substance checks |
| Paragraph evenness | words-per-paragraph CV at or under ~0.2 measured 16x, the strongest shape tell. Sections within ~15% of median length about 14x |
| Transition stacking | more than half of paragraphs opening with Furthermore/Moreover/Additionally/Consequently/Ultimately |
| Opening-word repetition | three+ consecutive paragraphs with the same opener |
| Em dash density | project ban is zero. Forensic signal alone is weak below ~20 per 1000 words |

Moreover and additionally individually measure human-leaning on 2026 models. The stacking pattern, not the words, marks metronome drafting.

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
| let me know if / want me to / happy to walk through | chat pivot left in docs |
| as of my last update / knowledge cutoff disclaimers | cutoff leakage |
| Final Thoughts / In conclusion heading | filler closer, weakened tell (~1.8x) |

## Dead and reversed tells (2026 measurement)

Measured on 21 current models against structured human baselines. Do not flag these as AI markers, and do not strip them reflexively from human text.

- when it comes to, a variety of, a plethora of, myriad, in this article: human markers, 0.0x to 0.2x
- in short, simply put, in essence: human-leaning or neutral
- moreover, additionally: human-leaning as single uses
- delve into, in the realm of, it is important to note: dead on 2026 models
- missing bullet lists: leans machine. Humans list in 34% of sections, AI in 18%
- SEO-style keyphrase echo: human-leaning, 9.4% vs 5.1%
- burstiness alone: near chance, AUROC ~0.52

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
2. Paragraph and sentence-length evenness
3. Hedging verbs and role-in-shaping formulas
4. Uncited numbers and floating authority
5. Triples, contrast tics, colon runways
6. Transition stacking and opener repetition
7. Style words and corporate verb inflation
8. Markdown leakage and project punctuation bans
