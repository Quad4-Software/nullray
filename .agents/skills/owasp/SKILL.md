---
name: owasp
description: >
  Apply focused OWASP checks to code changes, authentication, input handling,
  secrets, dependencies, logging, and authorization boundaries.
---

# OWASP review

Start with `audit_owasp` and `audit_deps`, then inspect data flow manually.

## Review order

1. Mark trust boundaries and attacker-controlled inputs.
2. Trace each input to interpreters, queries, templates, paths, and network requests.
3. Check authorization at the operation, object, and tenant boundary.
4. Check session expiry, credential storage, recovery, and replay resistance.
5. Check cryptographic choices and key lifecycle.
6. Check dependency locks, update policy, and build provenance.
7. Check logs and errors for credentials, tokens, personal data, and internal paths.
8. Add negative tests for denied access and malformed input.

Pattern scanners find a limited class of mistakes. Report their scope and inspect context before assigning severity.
