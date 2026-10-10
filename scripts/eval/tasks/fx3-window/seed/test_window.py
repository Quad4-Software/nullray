import unittest
from window import WindowAvg

class TestWindow(unittest.TestCase):
    def test_fills_up(self):
        w = WindowAvg(3)
        self.assertAlmostEqual(w.push(1), 1.0)
        self.assertAlmostEqual(w.push(2), 1.5)
        self.assertAlmostEqual(w.push(3), 2.0)
    def test_slides(self):
        w = WindowAvg(3)
        for x in [1, 2, 3]: w.push(x)
        self.assertAlmostEqual(w.push(6), (2+3+6)/3)
        self.assertAlmostEqual(w.push(9), (3+6+9)/3)
    def test_size_one(self):
        w = WindowAvg(1)
        self.assertAlmostEqual(w.push(4), 4.0)
        self.assertAlmostEqual(w.push(8), 8.0)
    def test_empty(self):
        self.assertAlmostEqual(WindowAvg(4).avg(), 0.0)

if __name__ == "__main__":
    unittest.main()
