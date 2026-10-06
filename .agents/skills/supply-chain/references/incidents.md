# Supply-chain incidents (teaching cases)

Read primary sources. Do not invent package lists or timestamps from memory.

## TanStack npm compromise (2026-05-11)

Primary: https://tanstack.com/blog/npm-supply-chain-compromise-postmortem

Follow-up: https://tanstack.com/blog/incident-followup

Chain (from the postmortem):

1. `pull_request_target` ran fork code in the base repo context
2. Shared Actions cache across fork and protected-branch trust boundaries
3. Poisoned cache restored on a legitimate main release job
4. OIDC token extracted from runner process memory
5. Malicious versions published through the legitimate pipeline with valid
   provenance

Lesson: SLSA/OIDC prove builder identity. They do not prove the build was free
of attacker-controlled steps.

## Mini Shai-Hulud (StepSecurity)

Writeup: https://www.stepsecurity.io/blog/mini-shai-hulud-is-back-a-self-spreading-supply-chain-attack-hits-the-npm-ecosystem

Self-spreading npm worm class that can ride maintainer credentials and produce
attestations when it hijacks the real publish path. Treat install hosts that
ran affected versions as credential-compromise candidates.

## Hardening derived from these cases

1. Remove `pull_request_target` that checks out and builds untrusted PR code
2. Split caches by trust boundary (fork PR vs protected branch)
3. Minimize `id-token: write` to protected release jobs
4. Do not restore PR-writable caches into release workflows
5. After a bad install, rotate cloud, forge, registry, and SSH credentials

Pair with [ci-pinned-actions](../../ci-pinned-actions/SKILL.md) for SHA pins.
