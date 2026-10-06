# Testing methods reference

Companion to the software-testing skill. Pick a method for the risk, then name
the oracle before writing asserts.

## Example-based unit tests

Hand-picked inputs and expected outputs. Best for regressions and clear
business cases. Weak at exploring large input spaces.

Name the test after the behavior. One behavior per test when failure triage
matters. Prefer sociable units for pure logic. Use doubles only for awkward
collaborators (remote IO, clocks, entropy).

## Table-driven tests

Same assertion over rows of input and expected output. Common in Go and useful
anywhere branch tables grow.

Keep rows data-only. Put setup outside the loop. Failures must print the row
key so a miss does not require a debugger.

## Property-based testing (PBT)

Declare invariants. The framework generates inputs and searches for
counterexamples. Shrink failures to minimal reproducers and keep them as fixed
examples.

### Invariant properties

| Property | Example |
|----------|---------|
| Round-trip | decode(encode(x)) equals x |
| Idempotence | f(f(x)) equals f(x) |
| Bounds | length, checksum, or balance stays in range |
| Conservation | tokens in equals tokens out after transform |
| Ordering | sort preserves multiset and is nondecreasing |

### Metamorphic properties

You may not know the exact output. You know how related inputs must relate.

Examples: doubling a filter window does not shrink the result set. Permuting
commutative inputs leaves the answer unchanged. Adding a no-op operation leaves
observable state unchanged.

### Differential properties

Run two paths on the same inputs. They must agree, or differ only where the
spec allows.

Examples: new parser vs old parser. Optimized path vs naive reference. Local
fake vs recorded vendor fixture for a frozen protocol version.

### Stateful properties

Model a system as commands and an abstract state. Generate command sequences.
After each step, compare concrete state to the model (or check model invariants).

Use for FSMs, caches, CRDTs, queues, and session machines. Keep the model
smaller than the implementation. Shrink command lists on failure.

Tools by ecosystem: Hypothesis (Python), fast-check (JS/TS), QuickCheck family
(Haskell and ports), testing/quick (Go), proptest (Go).

CI: fix a seed (or record and replay shrinks). Cap `numRuns` so PR time stays
predictable. Raise runs nightly on hot packages.

## Mutation testing

Insert small artificial bugs (flip conditions, change bounds, delete returns).
If tests still pass, the mutant survived and the suite is weak.

Use on critical packages periodically. It is expensive. Prefer improving
asserts over adding redundant tests that do not kill mutants. Ignore equivalent
mutants (changes that cannot change observable behavior) after review.

Tools: Stryker (JS/TS, .NET, Scala), PIT (JVM).

## Consumer-driven contracts

Consumer-driven contracts capture what a caller expects. Providers verify those
contracts in their CI without a full multi-service E2E matrix.

Use when services deploy independently. Skip when one monolith owns both sides
and integration tests already cover the boundary cheaply.

Workflow (Pact-style):

1. Consumer tests record interactions against a mock provider
2. Publish the pact
3. Provider verifies the pact against the real implementation
4. Gate deploy with can-i-deploy when a broker tracks verification status

Match on shapes and types, not brittle exact values, unless exactness is the
contract.

## Schema contracts for vendor APIs

For third-party APIs you do not control, consumer-driven pacts may not apply.
Pin OpenAPI / JSON Schema / protobuf contracts and validate responses (and
requests you send) in CI.

| Check | When |
|-------|------|
| Response validates against pinned schema | Every PR that touches the client |
| Breaking-change diff of vendor schema | When bumping the pin |
| Recorded fixtures for critical paths | Offline CI without live vendor |

Treat schema drift as a release risk, not a surprise at runtime.

## Characterization, golden master, approval, snapshot

Lock current behavior before refactor when intent is unclear. Michael Feathers
calls these characterization tests. Golden master, approval, and snapshot tools
are common implementations.

1. Drive the code with representative inputs
2. Capture output as the approved baseline
3. Fail on any unintended diff
4. Re-approve only after human review of the delta

### Noise normalization

Snapshots fail on noise if you capture raw dumps. Normalize before compare:

- Timestamps, UUIDs, request ids
- Absolute paths and temp dirs
- Map iteration order (sort keys)
- Floating noise (round or use tolerances)
- Locale-dependent formatting

Prefer asserting a smaller, stable span over approving a whole tree. Blind
snapshot updates hide regressions.

## Fuzzing

Generate or mutate inputs to find crashes, hangs, and assertion failures.
Coverage-guided fuzzers (libFuzzer, AFL family, go-fuzz, cargo-fuzz) prefer
paths that hit new branches.

Good targets: parsers, codecs, deserializers, path joiners, protocol decoders.
Run short smoke fuzzes on PR for hot parsers. Run longer campaigns nightly.
Keep crash corpora under version control when they stay small and sanitised.

Pair with sanitizers (ASan, UBSan, Miri) when available for the language.

## Deterministic simulation and chaos

Distributed and concurrent systems hide bugs behind scheduling and faults.
Deterministic simulation replays the same random seed and event order so a
failure reproduces.

Inject faults the product must survive: process kill, disk full, clock skew,
network partition, delayed messages. Assert invariants (safety and liveness
where practical), not only "did not crash".

Antithesis-style platforms run the whole stack under controlled fault schedules.
Chaos engineering in production remains complementary and needs blast-radius
limits. Prefer simulation in CI for regressions you can reproduce.

## Visual regression

Capture screenshots or DOM snapshots of critical UI states. Diff against a
baseline. Keep the set small: home, auth, primary flow, one dense data view.

Stabilize fonts, viewport, animations, and locale. Mask dynamic regions.
Playwright and similar runners support screenshot compare. Treat visual diffs
like approval tests: review before updating baselines.

## Accessibility testing

Automate checks that catch missing names, contrast failures, and broken
landmarks (axe-core and similar). Pair with keyboard-only smoke on primary
flows. Automated a11y does not replace assistive-tech sampling for high-impact
surfaces.

## Performance budgets

Define numeric budgets: p95 latency, payload size, memory ceiling, binary size.
Fail CI when a PR blows the budget on a fixed workload.

Keep perf tests deterministic: warm once, pin hardware class or use relative
deltas with wide tolerance only when absolute numbers are noisy. Gate PRs on
fast smoke budgets. Run heavier load suites nightly.

## Security testing placement

| Layer | What belongs |
|-------|--------------|
| Unit / package | Authz predicates, parser reject cases, secret redaction |
| Integration | Sandbox denies, TLS config, token expiry paths |
| E2E / smoke | Login and privilege boundary journeys only |
| CI scanners | Fast SAST every PR. Deeper CodeQL / SCA on schedule |
| Hunt / adversarial | Manual or agent-led oracles (bug-hunting skill) |

Do not rely on scanners alone for logic bugs. Do not duplicate full vuln hunts
inside every unit suite.

## Integration tests

Exercise real adapters: filesystem, Landlock, network clients, databases. Scope
them to boundaries that unit tests cannot fake honestly. Prefer testcontainers
or local fakes with faithful protocols.

## End-to-end tests

Protect revenue paths and smoke deployments. Keep the count small. Parallelize
carefully. Avoid duplicating business-rule coverage already held at lower layers.

## Flaky-test handling

1. Confirm flake rate (retries hide cost. Measure it)
2. Quarantine with an owner and expiry. Do not delete signal silently
3. Fix root cause: shared state, time, network, order dependence
4. Prefer fake clocks and isolated fixtures over heavier retries
5. Re-enable only after a green streak under stress (shuffle, parallel)

A flaky suite teaches the team to ignore red builds.

## Test smells

| Smell | Why it hurts | Remedy |
|-------|--------------|--------|
| Ice-cream cone | Most coverage in slow UI tests | Push checks down |
| Eager mocks | Tests pass while real wiring is wrong | Sociable tests or contracts |
| Giant fixtures | Obscure cause of failure | Minimal arrange per case |
| Multiple asserts for unrelated facts | Ambiguous failures | Split or use table rows |
| Testing private internals | Brittle refactors | Assert through public API |
| Comment-only intent | No executable oracle | Encode the property |
| Copy-paste cases | Drift between siblings | Table-driven or PBT |

## Mapping to CI

| Cadence | Suites |
|---------|--------|
| Every PR | Unit, table-driven, fast PBT seeds, fast integration, format, lint, typecheck, fast SAST, a11y smoke, perf smoke budgets |
| Nightly | Higher PBT runs, mutation on hot packages, full CodeQL, broad E2E, visual baselines, longer fuzz, simulation campaigns |
| Release | Full E2E, SCA policy, signed artifact checks, contract can-i-deploy |

## Choosing depth

Start with example and table-driven tests for known cases. Add PBT when the
input space is large and invariants are clear. Add contracts at deploy
boundaries. Add mutation when green suites still ship logic bugs. Add fuzz and
simulation when crash or concurrency risk dominates. Always pair the method with
an oracle from [oracles.md](oracles.md).
