import unittest
from bucket import TokenBucket

class TestBucket(unittest.TestCase):
    def test_starts_full(self):
        self.assertEqual(TokenBucket(1, 5).available(0), 5)
    def test_take_within(self):
        b = TokenBucket(1, 5)
        self.assertTrue(b.take(3, 0))
        self.assertEqual(b.available(0), 2)
    def test_denied_keeps(self):
        b = TokenBucket(0, 4)
        self.assertFalse(b.take(5, 0))
        self.assertEqual(b.available(1), 4)
    def test_refill(self):
        b = TokenBucket(2, 10)
        b.take(10, 0)
        self.assertFalse(b.take(1, 0.4))
        self.assertTrue(b.take(2, 1))
    def test_refill_capped(self):
        b = TokenBucket(100, 5)
        self.assertTrue(b.take(5, 0))
        self.assertEqual(b.available(10), 5)
    def test_frac_floor(self):
        b = TokenBucket(1, 10)
        b.take(10, 0)
        self.assertEqual(b.available(0.5), 0)
        self.assertEqual(b.available(1.5), 1)

if __name__ == "__main__":
    unittest.main()
