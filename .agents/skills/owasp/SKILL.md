---
name: owasp
description: >
  Apply focused OWASP checks to code changes, authentication, input handling,
  secrets, dependencies, logging, and authorization boundaries.
---

# OWASP review

Start with audit_owasp and audit_deps (or --audit). Then trace data flow by hand.

audit_owasp flags secrets and tokens, shell/eval sinks, SQL string concat, XSS sinks, path traversal near file opens, and a few unsafe deserializers. It does not prove absence of vulns.

## Review order

1. Mark trust boundaries and attacker-controlled inputs.
2. Trace each input to interpreters, queries, templates, paths, and network requests.
3. Check authorization at the operation, object, and tenant boundary.
4. Check session expiry, credential storage, recovery, and replay resistance.
5. Check cryptographic choices and key lifecycle.
6. Check dependency locks, update policy, and build provenance.
7. Check logs and errors for credentials, tokens, personal data, and internal paths.
8. Add negative tests for denied access and malformed input.

Report scanner scope when citing audit_* results. Inspect context before severity.
