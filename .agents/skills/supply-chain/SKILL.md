---
name: supply-chain
description: >
  Software supply-chain attacks, SLSA provenance limits, Sigstore/cosign, and
  CI cache or OIDC abuse (including Mini Shai-Hulud / TanStack 2026). Use when
  hardening releases, reviewing Actions, or verifying signed artifacts.
---

# Supply chain

Load this skill for dependency, CI, release signing, or provenance work.
Signatures and SLSA attestations prove build identity. They do not prove the
build inputs or workflow were honest.

## Agent workflow

1. Name the artifact and the identity you expect (repo, workflow, signer)
2. State what verification proves vs what it does not (table below)
3. Inspect CI for `pull_request_target`, shared caches, and `id-token: write`
4. Pin Actions to full SHAs ([ci-pinned-actions](../ci-pinned-actions/SKILL.md))
5. Verify cosign/SLSA in deploy, then still review high-impact dependency diffs
6. On known-bad installs, rotate credentials before treating the host as clean

Detail: [references/slsa-cosign.md](references/slsa-cosign.md).
Incidents: [references/incidents.md](references/incidents.md).
URLs: [references/urls.md](references/urls.md).

## Core claim limits

| Control | Proves | Does not prove |
|---------|--------|----------------|
| Cosign / Sigstore signature | Who signed with which identity | Code was benign |
| npm provenance / SLSA L2 | Built at claimed repo/workflow | Isolated, unpoisoned build |
| SLSA Build L3 (real isolation) | Hardened builder properties | Upstream source review |
| Lockfiles | Reproducible resolves | Maintainer account safety |

## Hardening checklist

1. Ban `pull_request_target` with checkout of fork code and writable caches
2. Separate caches by trust boundary (PR forks vs protected branches)
3. Scope `id-token: write` only on protected, minimal release jobs
4. Keep signing credentials out of build steps that execute untrusted inputs
5. Pin Actions to full SHAs (see [ci-pinned-actions](../ci-pinned-actions/SKILL.md))
6. Prefer immutable releases and deprecate yankable tags
7. Verify cosign/SLSA in deploy, then still review high-impact dependency diffs

## Install-time risk

Lifecycle scripts (`preinstall`, `prepare`) are code execution. Use ignore
scripts in CI when possible. Rotate credentials after a known bad install.

## Related

- [attack-surface](../attack-surface/SKILL.md) for TOCTOU / RCE / DoS classes
- [rngit](../rngit/SKILL.md) for Ed25519 `.rsm` release manifests over Reticulum
- [code-quality-tools](../code-quality-tools/SKILL.md) for SAST/SCA gates

## Research URLs

Full list: [references/urls.md](references/urls.md).

- SLSA v1.2: https://slsa.dev/spec/v1.2/
- TanStack postmortem: https://tanstack.com/blog/npm-supply-chain-compromise-postmortem
- StepSecurity Mini Shai-Hulud: https://www.stepsecurity.io/blog/mini-shai-hulud-is-back-a-self-spreading-supply-chain-attack-hits-the-npm-ecosystem
- GitHub pwn-request guidance: https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/
