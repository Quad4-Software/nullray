---
name: software-testing
description: >
  Modern software testing strategy: pyramid cost model, property-based and
  metamorphic tests, mutation testing, contracts, characterization and approval
  tests, fuzzing, and CI placement. Use when designing test plans, strengthening
  weak suites, or choosing an oracle for a risk.
---

# Software testing

Load this skill when planning tests, repairing flaky or weak suites, or picking
methods beyond happy-path examples. For nullray package and adversarial tests,
use `make test` and [bug-hunting](../bug-hunting/SKILL.md).

## Cost model (pyramid)

| Layer | Intent | Volume |
|-------|--------|--------|
| Unit / package | Fast feedback on pure logic | Many |
| Integration | Real boundaries (DB, FS, HTTP, sandbox) | Targeted |
| End-to-end | Critical user journeys | Few |

The pyramid is incomplete alone. Add the methods below at risky boundaries.

## Method picker

| Situation | Method |
|-----------|--------|
| Invariants, parsers, codecs, permissions | Property-based (PBT) |
| Compare to a trusted reference | Differential testing |
| Output transforms that must preserve relations | Metamorphic testing |
| Protocol or UI with state machines | Stateful PBT |
| High coverage, weak asserts suspected | Mutation testing |
| Service or vendor API drift | Contract / schema tests |
| Legacy refactor without specs | Characterization / golden / approval |
| Untrusted parsers and codecs | Fuzzing |
| Distributed timing and faults | Deterministic simulation / chaos |
| UI regressions | Sparse E2E + visual checks |
| Assert strength unknown | Mutation score on hot packages |

Detail: [references/methods.md](references/methods.md).
Oracle choice: [references/oracles.md](references/oracles.md).
URLs: [references/urls.md](references/urls.md).

## Writing good tests

1. Name the behavior and the oracle
2. Pin PBT seeds in CI when failures must reproduce
3. Assert behavior, not implementation trivia
4. Normalize snapshot noise (time, ids, order) before approval
5. Treat flakes as defects. Quarantine with a tracked fix
6. Scope contracts to fields you actually read

## Coverage

Coverage shows what ran. It does not prove asserts catch bugs. Pair line
coverage with mutation analysis on critical packages.

## CI cadence

| Cadence | Suites |
|---------|--------|
| Every PR | Unit, fast integration, format, lint, typecheck, fast SAST |
| Nightly | Mutation on hot packages, broader E2E, perf smoke, deep SAST |
| Release | Full E2E, SCA policy, signed artifact checks |

## nullray posture

- Package tests with `-define:ODIN_TEST_THREADS=1`
- Adversarial focus in sandbox and tools/shell
- `--self-test`, print-smoke, optional chat-smoke
- Prefer accept/reject oracles over pattern-match reports
