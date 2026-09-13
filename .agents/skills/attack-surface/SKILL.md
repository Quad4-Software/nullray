---
name: attack-surface
description: >
  Common software attack vectors and footguns: TOCTOU, path traversal, DoS,
  OOM, RCE classes, and insecure defaults. Use when threat-modeling code,
  reviewing parsers, or hardening file and network handling.
---

# Attack surface

Load this skill when reviewing for exploitable classes beyond a single CWE
checklist. Pair with [owasp](../owasp/SKILL.md) and
[bug-hunting](../bug-hunting/SKILL.md).

## Agent workflow

1. List attacker-controlled inputs (bytes, paths, headers, uploads, URLs)
2. Mark trust boundaries those inputs cross
3. Ask the review questions below before proposing fixes
4. Prefer openat / capability roots / streaming limits over check-then-act
5. Report severity, path:line, attacker control, impact, short repro
6. Cross-link language skills (go, rust, python) for concrete APIs

## Class map

| Class | Typical bug | First defense |
|-------|-------------|----------------|
| TOCTOU | check then use on files | openat / O_NOFOLLOW / capability root |
| Path traversal | `../` or absolute user paths | Join + root confine |
| RCE | unsafe deser, template inject, shell join | avoid eval surfaces |
| DoS | huge alloc, zip bomb, regex | limits and timeouts |
| OOM | unbounded buffers | cap sizes, stream |
| Authz bypass | IDOR, missing checks | explicit allow decisions |
| SSRF | URL fetch from user | allowlist hosts/schemes |
| Supply chain | malicious dep/CI | see supply-chain skill |

Detail: [references/toctou.md](references/toctou.md),
[references/resource-abuse.md](references/resource-abuse.md).

## Review questions

1. What does the attacker control (bytes, paths, headers, uploads)?
2. Which trust boundary does that input cross?
3. Is there a time gap between check and use?
4. Are sizes, depths, and timeouts bounded?
5. Can failure modes leak secrets or amplify load?

## Language notes

- Go: `path` vs `filepath`, rooted opens, decoder limits
- Rust: `cap-std`, avoid exists-then-open
- Python: pickle RCE, tarfile traversal, tempfile races
- Odin/C: manual lengths, integer truncate, FFI lifetimes

## Reporting

Severity, path:line, attacker control, impact, short repro. Do not claim
exploitability without a plausible path.

## Research URLs

Full list: [references/urls.md](references/urls.md).

- CWE-367 TOCTOU: https://cwe.mitre.org/data/definitions/367.html
- CWE-22 path traversal: https://cwe.mitre.org/data/definitions/22.html
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- openat2: https://man7.org/linux/man-pages/man2/openat2.2.html

