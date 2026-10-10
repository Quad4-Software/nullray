# token bucket

Implement `bucket.py` with a `TokenBucket` class:

    b = TokenBucket(rate, capacity)

- `rate` tokens per second refill, `capacity` max held tokens (int).
- The bucket starts full.
- `b.take(n, now)` returns True and removes n tokens if at least n are
  held at time `now` (monotonic seconds), refilling first at `rate`.
  Otherwise returns False and takes nothing.
- `b.available(now)` returns the int floor of held tokens at `now`.
- Refill may never exceed capacity. `now` may go backward in test (never does in tests here).

`test_bucket.py` is the contract and must pass unchanged.
