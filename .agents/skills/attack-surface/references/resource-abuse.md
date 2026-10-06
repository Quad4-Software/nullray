# DoS, OOM, and RCE classes

## DoS / OOM

Untrusted input must not force unbounded CPU, memory, disk, or goroutine/thread
counts.

| Source | Cap |
|--------|-----|
| Request bodies | Max bytes + timeouts |
| Nested JSON/XML | Max depth |
| Archives | Max files, max uncompressed size, max ratio |
| Regex | Avoid user-controlled patterns. Prefer linear engines |
| Fan-out jobs | Worker pools and queues |
| Decompression | Streaming with limits |

Return clear errors. Do not retry amplification loops on attacker input.

## RCE classes

| Surface | Safer approach |
|---------|----------------|
| `eval` / `exec` of user strings | Structured APIs only |
| Shell with concatenated args | argv arrays, no shell |
| Unsafe deserialization | json/protobuf with allowlists |
| Template engines with code exec | Auto-escape. No user templates as code |
| Native memory corruption | Memory-safe languages, fuzzers, sanitizers |

RCE often starts as a "feature" (plugins, expressions, macros). Treat those as
full trust boundaries.

## Amplification

One cheap request that triggers many downstream calls is still DoS. Rate-limit
and bulkhead external dependencies.
