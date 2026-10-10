import unittest
from retry import with_retry

class Seq:
    def __init__(self, vals): self.vals, self.i = vals, 0
    def __call__(self):
        v = self.vals[self.i]; self.i += 1
        return v

class TestRetry(unittest.TestCase):
    def test_eventual_none_returns_value(self):
        self.assertEqual(with_retry(Seq([None, None, "x"]), sleep=lambda s: None), "x")
    def test_all_none_returns_none(self):
        self.assertIsNone(with_retry(Seq([None] * 5), sleep=lambda s: None))
    def test_calls_exactly_attempts_times(self):
        f = Seq([None] * 10)
        with_retry(f, attempts=4, sleep=lambda s: None)
        self.assertEqual(f.i, 4)
    def test_backoff_doubles(self):
        delays = []
        with_retry(Seq([None] * 3), attempts=3, base_delay=0.01, sleep=delays.append)
        self.assertEqual(delays, [0.01, 0.02])
    def test_delay_capped(self):
        delays = []
        with_retry(Seq([None] * 3), attempts=3, base_delay=0.5, max_delay=0.6, sleep=delays.append)
        self.assertEqual(delays, [0.5, 0.6])
    def test_exception_reraises_last(self):
        calls = [0]
        def boom():
            calls[0] += 1
            raise RuntimeError(f"boom{calls[0]}")
        with self.assertRaises(RuntimeError) as cm:
            with_retry(boom, attempts=2, sleep=lambda s: None)
        self.assertEqual(str(cm.exception), "boom2")
        self.assertEqual(calls[0], 2)

if __name__ == "__main__":
    unittest.main()
