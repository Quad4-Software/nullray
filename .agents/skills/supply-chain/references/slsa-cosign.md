# SLSA and cosign claim limits

## SLSA

Spec: https://slsa.dev/spec/v1.2/

SLSA describes increasing guarantees about how an artifact was built and how
that fact is attested. It does not claim the source code is free of bugs or
backdoors.

| Claim people make | What verification actually checks |
|-------------------|-----------------------------------|
| "Has provenance" | Attestation exists and parses |
| "Signed by CI" | Identity matches expected builder / workflow |
| "SLSA Build L3" | Builder isolation properties for that platform |

Valid provenance can still cover a poisoned build if the attacker controls the
builder inputs or runner memory. TanStack May 2026 is the teaching case.

## Cosign / Sigstore

Signatures bind an identity (OIDC subject, key) to a digest. Verify:

1. Digest matches the artifact you will run
2. Identity matches the expected publisher
3. Rekor / transparency log policy if your org requires it

A correct signature still says nothing about whether the signed bytes are safe.

## npm provenance

npm provenance ties a publish to a GitHub Actions (or similar) identity. Treat
it as build-identity evidence. Still review dependency diffs and lifecycle
scripts.

## Practical verify loop

1. Pin expected identity (repo, workflow, ref protection)
2. Verify signature or provenance in deploy
3. Diff lockfiles and high-impact dependency changes
4. Block `pull_request_target` + shared writable caches across trust boundaries
5. Rotate credentials after a known-bad install
