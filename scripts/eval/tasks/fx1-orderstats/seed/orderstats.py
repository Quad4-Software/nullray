"""k-th smallest via quickselect. Failing test tells you where it breaks."""

def kth_smallest(nums, k):
    if not 1 <= k <= len(nums):
        raise ValueError("k out of range")
    return _select(list(nums), 0, len(nums) - 1, k - 1)


def _select(a, lo, hi, k):
    pivot = a[lo]
    i = lo
    for j in range(lo + 1, hi + 1):
        if a[j] <= pivot:
            i += 1
            a[i], a[j] = a[j], a[i]
    a[lo], a[i] = a[i], a[lo]
    if i == k:
        return a[i]
    if i < k:
        return _select(a, i, hi, k)   # BUG: duplicates need i+1 bound
    return _select(a, lo, i - 1, k)
