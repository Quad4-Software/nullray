# Choosing an oracle

An oracle accepts or rejects a claim about behavior without trusting the buggy
path alone. Pick the oracle from the risk, then pick the test method that can
feed it inputs.

For vuln hunts, also see [bug-hunting oracles](../../bug-hunting/references/oracles.md).

## Quick picker

| Risk | Prefer this oracle | Typical method |
|------|--------------------|----------------|
| Wrong result on known case | Exact expected value | Example / table-driven |
| Large input space, clear law | Stated invariant | Property-based |
| Exact answer unknown, relations known | Metamorphic relation | PBT with related inputs |
| Rewrite or dual implementation | Agreement of two paths | Differential |
| Protocol / FSM corruption | Model vs concrete state | Stateful PBT |
| Crash, hang, memory unsafety | Process survival + sanitizer | Fuzzing |
| Weak asserts in a green suite | Mutant killed | Mutation testing |
| Service boundary drift | Consumer expectation held | Pact / contract verify |
| Vendor response shape drift | Schema validation | Schema contract |
| Legacy refactor safety | Output matches approved baseline | Characterization / approval |
| UI polish regression | Pixel or DOM baseline | Visual regression |
| Inclusive UI defects | Automated a11y rules + keyboard path | axe + manual smoke |
| Perf regression | Budget not exceeded | Perf budget gate |
| Authz bypass | Denied principal stays denied | Negative test |
| Sandbox / FS escape | Deny holds under attack input | Integration + adversarial |
| Distributed safety under faults | Invariant holds across schedules | Deterministic simulation |

## Oracle catalog

### Exact example

Accept when output equals a hand-checked expectation. Reject otherwise.

Use for regressions and business rules with small, stable fixtures. Do not use
as the only oracle for parsers or codecs with huge domains.

### Invariant

Accept when a property holds for generated inputs. Reject on the first
counterexample (after shrink).

Write the property in one sentence before coding. If you cannot name it, you
are not ready for PBT.

### Metamorphic

Accept when related inputs produce related outputs. Reject when the relation
breaks.

Use when a full ground-truth oracle is expensive or unknown (search ranking,
ML-ish heuristics, complex numerics with tolerance bands).

### Differential

Accept when path A and path B agree (within allowed delta). Reject on unsafe
disagreement.

Keep one path trusted or slow. If both paths share a bug, the oracle is blind.
Rotate references when possible.

### Model / stateful

Accept when the concrete system matches an abstract model after each command,
or when model invariants still hold. Reject on divergence.

The model must be simpler than the system under test. A model that copies the
implementation proves nothing.

### Characterization / approval

Accept when current output matches the approved baseline after normalization.
Reject on diff.

This oracle documents actual behavior, not desired correctness. Promote
important cases to exact or invariant oracles once intent is known.

### Negative / deny

Accept when a forbidden action fails closed. Reject when the deny is skipped.

Required for authz, tenant isolation, sandbox, and secret redaction. A positive
path test alone is not enough.

### Survival / sanitizer

Accept when the process stays well-defined (no crash, no sanitizer fire, no
hang past timeout). Reject on fault.

Fuzzing often uses this oracle. Add stronger oracles when you can (round-trip
after parse, invariant on surviving runs).

### Contract / schema

Accept when the interaction matches the pact or the payload validates against
the pinned schema. Reject on mismatch.

Contracts catch boundary drift. They do not prove business correctness inside
either service.

### Mutant kill

Accept suite quality when a seeded fault causes a test failure. Reject when the
mutant survives.

This oracles the test suite, not the product. Run it to find missing asserts.

### Budget

Accept when measured cost stays under a numeric limit. Reject when a PR or
build exceeds it.

Budgets need a fixed workload and stable environment class. Wide noise bands
without investigation become rubber stamps.

### Visual / a11y rule

Accept when screenshot or axe rules pass against baseline / WCAG checks.
Reject on unexpected diff or rule failure.

Automate the cheap checks. Sample real assistive tech for high-impact screens.

## How to choose under pressure

1. Name the failure you fear (wrong answer, crash, leak, drift, slow)
2. Name one observation that would prove it false
3. If you lack ground truth, use metamorphic, differential, or characterization
4. If the domain is huge, prefer generated inputs over more hand examples
5. If the suite is green but bugs ship, oracle the suite with mutation
6. If deploy boundaries move independently, oracle the contract, not only E2E

## Anti-patterns

| Anti-pattern | Problem |
|--------------|---------|
| Scanner finding as oracle | Pattern match is a lead, not proof |
| Snapshot of unnormalized noise | Permanent flake or blind re-approve |
| Mock expectations as sole proof | Wiring and vendor drift stay untested |
| Coverage percentage as oracle | Execution without useful asserts |
| "Looks right" in review only | No executable accept/reject |

Write the oracle before arguing severity or merging a flaky quarantine.
