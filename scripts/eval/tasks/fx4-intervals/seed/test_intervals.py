import unittest
from intervals import merge

class TestMerge(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(merge([(1,3),(2,6),(8,10)]), [(1,6),(8,10)])
    def test_touching(self):
        self.assertEqual(merge([(1,4),(4,5)]), [(1,5)])
    def test_unsorted(self):
        self.assertEqual(merge([(8,10),(1,3),(2,6)]), [(1,6),(8,10)])
    def test_contained(self):
        self.assertEqual(merge([(1,10),(2,3),(4,5)]), [(1,10)])
    def test_empty(self):
        self.assertEqual(merge([]), [])
    def test_single(self):
        self.assertEqual(merge([(7,9)]), [(7,9)])
    def test_chain(self):
        self.assertEqual(merge([(1,3),(2,4),(3,5),(5,7)]), [(1,7)])

if __name__ == "__main__":
    unittest.main()
