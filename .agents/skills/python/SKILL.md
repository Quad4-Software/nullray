---
name: python
description: >
  Python 3.14 features: free-threaded builds, t-strings (PEP 750), deferred
  annotations, subinterpreters, and stdlib changes. Use when writing or
  upgrading Python 3.14 code or choosing concurrency models.
---

# Python 3.14

Load this skill for Python 3.14+ work. First stable 3.14.0: 2025-10-07.
Confirm current patch and feature status on
https://docs.python.org/3/whatsnew/3.14.html before citing version numbers.

## Agent workflow

1. Check `python --version` (and `python3.14t` if free-threaded is in scope)
2. Skim the official whatsnew page for removals that touch this repo
3. Prefer t-strings for structured sinks. Keep f-strings for plain text
4. Do not enable free-threaded production paths without a C-extension audit
5. Cap pickle, tar extraction, and parsers. See attack-surface
6. Run the project test suite on 3.14 before claiming upgrade complete

Detail: [references/py314.md](references/py314.md).
URLs: [references/urls.md](references/urls.md).

## Headline features

| Feature | Notes |
|---------|-------|
| Free-threaded CPython (PEP 779) | Officially supported. Still opt-in build. ~5-10% single-thread cost |
| t-strings (PEP 750) | `t"..."` yields a Template, not `str`. Safe custom processing |
| Deferred annotations | Lazy evaluation via `annotationlib` |
| Multiple interpreters | Stdlib support for subinterpreters |
| Experimental JIT | Available on some Windows/macOS binaries |
| Zstandard | Stdlib support |
| Safer external debugger | Restricted debug interface |

## t-strings

```python
from string.templatelib import Template

def html(template: Template) -> str:
    # Process static parts and interpolations separately
    ...

name = "<script>"
html(t"<p>{name}</p>")  # sanitizer sees structure, not a finished str
```

Use t-strings when sinks need structured interpolation (HTML, SQL builders,
shell). Keep f-strings for plain formatting.

## Free-threaded mode

- Ship both GIL and free-threaded builds. Pick explicitly
- Audit C extensions for thread safety before enabling in production
- Prefer `concurrent.futures` and queues over ad-hoc shared mutables

## Footguns

- Do not treat free-threaded as "no races". Memory model still needs locks or
  message passing
- Untrusted pickle remains RCE. Prefer safer formats
- Path operations: resolve under a root. Watch symlink TOCTOU
- Cap recursion and parser depth for DoS

Pair with [attack-surface](../attack-surface/SKILL.md) and
[supply-chain](../supply-chain/SKILL.md) for install and CI risks.

## Research URLs

Full list: [references/urls.md](references/urls.md).

- What's new: https://docs.python.org/3/whatsnew/3.14.html
- PEP 750 (t-strings): https://peps.python.org/pep-0750/
- PEP 779 (free-threaded): https://peps.python.org/pep-0779/
- Free-threading howto: https://docs.python.org/3/howto/free-threading-python.html
