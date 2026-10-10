# AoC 2025 eval tasks

Generates Advent of Code 2025 task dirs for the eval driver. Each task
seeds a workspace with the puzzle input and the full problem statement,
asks for solve.py, and verifies by running it and matching the two
expected answers as whole output lines.

    python3 scripts/eval/aoc/fetch.py            # build all 12 days
    python3 scripts/eval/eval.py --tasks aoc-d01,aoc-d02 \
        --models opencode/deepseek-v4.1-flash,ollama/qwen3:8b

## Data sources

| Piece | Source |
|-------|--------|
| puzzle input | `nouhailaaziki/Advent-of-Code-2025` `dayNN/puzzle_input` |
| gold answers | computed locally by running that repo's `partN.py` |
| statement | `SolunarNexus/adventofcode2025` `day-NN-*/README.md` |

`--session COOKIE` (or `AOC_SESSION`) fetches your own inputs from
adventofcode.com instead; answers still come from the reference
implementation, which is input-agnostic.

Generated dirs (`scripts/eval/tasks/aoc-*`) and `answers.json` are
gitignored: AoC inputs are account-specific and the organizers ask that
inputs and puzzle text not be redistributed.

## Verify semantics

solve.py must print the Part 1 answer and then the Part 2 answer (day 12
has a single part). The verifier runs it under a 120s timeout and greps
for each expected answer as a complete output line, so labeled output
like `part 1: 42` still counts.

## Provider specs

`--models` entries may carry a provider prefix: `opencode/deepseek-v4.1-flash`,
`openrouter/qwen/...`, `ollama/qwen3:8b`. A bare model name uses the
configured default provider.
