"""Retry-with-backoff helper. Tests show the intended contract."""
import time

def with_retry(fn, attempts=3, base_delay=0.01, max_delay=1.0, sleep=time.sleep):
    """Call fn() until it returns a non-None value or attempts are spent.
    Sleeps base_delay * 2**i between tries, capped at max_delay.
    Returns fn()'s value, or raises the last exception / returns None."""
    for i in range(attempts):
        try:
            v = fn()
            if v is not None:
                return v
        except Exception:
            return None            # BUG: must re-raise on the last attempt
        sleep(min(base_delay * 2 ** i, max_delay))   # BUG: sleeps after the last attempt too
    return None
