# Authoritative URLs

Curated links for the software-testing skill. Prefer primary docs over blogs.

## Strategy and vocabulary

| Topic | URL |
|-------|-----|
| Testing guide (index) | https://martinfowler.com/testing/ |
| Test pyramid | https://martinfowler.com/bliki/TestPyramid.html |
| Practical test pyramid | https://martinfowler.com/articles/practical-test-pyramid.html |
| Test double | https://martinfowler.com/bliki/TestDouble.html |
| Unit test (solitary vs sociable) | https://martinfowler.com/bliki/UnitTest.html |
| Test coverage limits | https://martinfowler.com/bliki/TestCoverage.html |

## Property-based testing

| Topic | URL |
|-------|-----|
| Hypothesis (Python) | https://hypothesis.works/ |
| Hypothesis docs | https://hypothesis.readthedocs.io/en/latest/ |
| Hypothesis stateful tests | https://hypothesis.readthedocs.io/en/latest/stateful.html |
| fast-check (JS/TS) | https://fast-check.dev/ |
| What is PBT (fast-check) | https://fast-check.dev/docs/introduction/what-is-property-based-testing/ |
| Go testing/quick | https://pkg.go.dev/testing/quick |

## Mutation testing and coverage

| Topic | URL |
|-------|-----|
| Stryker Mutator | https://stryker-mutator.io/ |
| What is mutation testing (Stryker) | https://stryker-mutator.io/docs/ |
| PIT (JVM) | https://pitest.org/ |
| Fowler on coverage | https://martinfowler.com/bliki/TestCoverage.html |

Coverage answers "did this code run?". Mutation answers "would tests notice if
this code were wrong?". Use both. Do not treat a coverage percentage as proof.

## Contracts

| Topic | URL |
|-------|-----|
| Pact docs | https://docs.pact.io/ |
| Pact Broker / can-i-deploy | https://docs.pact.io/pact_broker/can_i_deploy |
| OpenAPI Specification | https://spec.openapis.org/oas/latest.html |
| JSON Schema | https://json-schema.org/ |

## Characterization and approval

| Topic | URL |
|-------|-----|
| Characterization testing (Feathers) | https://michaelfeathers.silvrback.com/characterization-testing |
| Characterization test (overview) | https://en.wikipedia.org/wiki/Characterization_test |
| ApprovalTests | https://approvaltests.com/ |

## UI, a11y, and browser automation

| Topic | URL |
|-------|-----|
| Playwright | https://playwright.dev/ |
| Playwright assertions / screenshots | https://playwright.dev/docs/test-assertions |
| axe-core | https://github.com/dequelabs/axe-core |
| WCAG 2 overview | https://www.w3.org/WAI/standards-guidelines/wcag/ |

## Fuzzing and simulation

| Topic | URL |
|-------|-----|
| libFuzzer | https://llvm.org/docs/LibFuzzer.html |
| AFL++ | https://aflplus.plus/ |
| Go fuzzing | https://go.dev/security/fuzz/ |
| Antithesis (deterministic simulation) | https://antithesis.com/docs/introduction/how_antithesis_works/ |
| Chaos Mesh (Kubernetes chaos) | https://chaos-mesh.org/ |

## Related nullray skills

| Skill | Path |
|-------|------|
| Bug hunting oracles | ../bug-hunting/references/oracles.md |
| Code quality / SAST placement | ../code-quality-tools/SKILL.md |
| Attack surface classes | ../attack-surface/SKILL.md |
