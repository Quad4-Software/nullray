# SAST and security scanning

## Roles

| Tool | Strength |
|------|----------|
| Semgrep | Fast multi-language pattern and taint rules, custom YAML rules, PR-friendly |
| CodeQL | Deep whole-program dataflow, strong for complex taint paths, heavier CI |
| Language analyzers | clippy, go vet, bandit, spotbugs, and friends for ecosystem idioms |
| Secret scanners | gitleaks, trufflehog for credential leaks |
| SCA | osv-scanner, npm/pnpm audit, Dependabot for dependency CVEs |

## Placement

- Semgrep (or equivalent fast SAST): every pull request
- CodeQL: main branch or nightly, plus high-risk repos on PR if budget allows
- Secret scan: every PR and pre-receive when available
- SCA: every PR, with fail policy on reachable high/critical when possible

## Writing findings

Report path, rule id, severity, why it is exploitable or not, and a minimal
fix. Mark false positives with a linked justification. Prefer fixing code
over broad suppressions.

## Not SAST

- Formatters
- Style linters
- Coverage percentage alone
- A green unit suite

Pair with [owasp](../../owasp/SKILL.md) and [bug-hunting](../../bug-hunting/SKILL.md)
when reviewing auth, injection, or sandbox boundaries.
