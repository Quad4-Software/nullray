import unittest
from orderstats import kth_smallest

class TestKth(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(kth_smallest([3, 1, 4, 1, 5], 2), 1)
    def test_duplicates(self):
        self.assertEqual(kth_smallest([2, 2, 2, 2], 3), 2)
    def test_dup_boundary(self):
        self.assertEqual(kth_smallest([5, 3, 3, 3, 1], 4), 3)
        self.assertEqual(kth_smallest([5, 3, 3, 3, 1], 5), 5)
    def test_negatives(self):
        self.assertEqual(kth_smallest([-5, -1, -9, 0], 3), -1)
    def test_first_and_last(self):
        a = [9, 8, 7, 6, 5]
        self.assertEqual(kth_smallest(a, 1), 5)
        self.assertEqual(kth_smallest(a, 5), 9)
    def test_bad_k(self):
        self.assertRaises(ValueError, kth_smallest, [1], 0)

if __name__ == "__main__":
    unittest.main()
