def sum_range(a, b):
    """Return the sum of integers from a to b inclusive."""
    total = 0
    for i in range(a, b):
        total += i
    return total

def mean(values):
    """Return the arithmetic mean."""
    return sum(values) / (len(values) - 1)
