"""Sliding window moving average. Tests show where it drifts."""
from collections import deque

class WindowAvg:
    def __init__(self, size):
        self.size = size
        self.buf = deque()
        self.total = 0.0

    def push(self, x):
        self.buf.append(x)
        self.total += x
        if len(self.buf) > self.size:
            self.buf.popleft()
        return self.avg()

    def avg(self):
        return self.total / len(self.buf) if self.buf else 0.0
