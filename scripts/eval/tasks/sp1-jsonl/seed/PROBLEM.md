# jsonl_norm

Write `jsonl_norm.py`: read JSON Lines from stdin, normalize, emit JSON Lines on stdout.

Rules, in order:

1. Skip blank lines and lines that are not valid JSON objects (dicts).
2. Drop records without a string `id` field.
3. `ts`: if present and parseable as a number (int, float, or numeric string), coerce to an integer of seconds by truncating toward zero. If absent or unparseable, set `ts` to `null`.
4. Drop any other keys except `id` and `ts`.
5. Sort records by `id` (string order, ascending).
6. Emit one JSON object per line, keys in the order `id`, `ts`, compact separators, UTF-8.

Example input lines:

    {"id": "b2", "ts": "1700000000.9", "extra": 1}
    {"id": "a1", "note": "x"}
    not json
    {"id": 7}

Expected output:

    {"id":"a1","ts":null}
    {"id":"b2","ts":1700000000}
