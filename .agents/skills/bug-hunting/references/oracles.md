# Oracles, exploratory, and adversarial hunts

## Why this mix works

Exploratory and adversarial passes surface unusual paths models miss on checklist-only review. Oracles stop hallucinated "vulns". Use both.

## Test oracles

An oracle accepts or rejects a hypothesis without trusting the buggy path.

| Oracle | Accept when | Reject when |
|--------|-------------|-------------|
| Repro | Concrete input triggers the bad effect | Cannot reproduce after honest try |
| Invariant | Stated property broken (authz, integrity, confidentiality) | Property still holds under attack input |
| Negative test | Denied role or tenant can still act | Denial holds |
| Differential | Two equivalent paths disagree unsafely | Paths agree or difference is intentional |
| Unreachable | No caller or gate makes the sink dead | Reachable from attacker-controlled input |

Write the oracle before arguing severity. Scanner output is not an oracle.

## Exploratory (creativity)

- Charter time-boxed areas. Do not boil the ocean.
- Ask "what if" on every trust boundary: wrong user, empty, huge, unicode, symlink, TOCTOU, partial write.
- Cross features: upload then path join, webhook then shell, template then HTML sink.
- Prefer bugs that hurt downstream users of the library or tool, not only local style.

## Adversarial framing

Pick a goal: secret theft, RCE, authz bypass, supply-chain implant, sandbox escape, DoS that burns CI or cloud spend. Walk the shortest path to that goal. Ignore issues that cannot feed the goal unless they are still critical on their own.

## Sampling notes

Higher temperature (explore / adversarial) increases path diversity. Lower temperature (oracle) increases consistency when confirming. Override with NULLRAY_TEMPERATURE and NULLRAY_TOP_P when comparing models. o-series style models may ignore sampling params.
