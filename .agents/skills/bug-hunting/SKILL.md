---
name: bug-hunting
description: >
  Hunt bugs and vulns with audit scanners, test oracles, exploratory creativity,
  and adversarial attacker framing. Use for security review, crash hunting,
  CVE-style digs, and open-source hardening.
---

# Bug hunting

Protect users of open-source software. Prefer critical and high impact issues.

## Automatic vs preset

| Setting | What it does |
|---------|----------------|
| `--hunt` / `NULLRAY_HUNT=auto` / `=1` | **Automatic two-pass in print mode**: phase 1 explore (temp 0.9), phase 2 oracle (temp 0.25). Combines both replies. |
| `explore` / `oracle` / `adversarial` / `balanced` | **Static preset** for the whole turn. Same temp until you change profile. |

Overrides always win: `NULLRAY_TEMPERATURE`, `NULLRAY_TOP_P`, `/temp`, `/top_p`.

TUI: `/hunt auto` sets review + explore phase. Switch with `/hunt oracle` for a confirm turn. Print `--hunt` runs both passes for you.

## Profiles

| Profile | Temp | Bias |
|---------|------|------|
| auto | 0.9 then 0.25 | explore leads, then oracle gate |
| balanced | 0.7 | single mid temp |
| explore | 0.9 | more hypotheses |
| oracle | 0.25 | confirm or kill |
| adversarial | 0.85 | attacker goals |

Compare models with the same profile (`-m`). Prefer `auto` for default hunts.

## First pass

1. Run audit_* (or --audit once). Treat highs as leads.
2. Prefer review mode.
3. load_skill owasp when tracing auth, crypto, or injection.

## Oracle + exploratory + adversarial

1. Charter an area.
2. Hypothesis before deep reading.
3. Exploratory: unusual inputs and trust-boundary crossings.
4. Adversarial: shortest path to secret theft, RCE, authz bypass, supply-chain harm, sandbox escape.
5. Oracle: independent accept/reject. Never report on pattern match alone.

Detail: [references/oracles.md](references/oracles.md).

## Report shape

Severity, path:line, attacker control, impact, short repro. End with FINDINGS: N or FINDINGS: none.

## Limits

Scanners miss logic bugs. Sampling helps exploration. Oracles decide. A clean --audit is not a security proof.
