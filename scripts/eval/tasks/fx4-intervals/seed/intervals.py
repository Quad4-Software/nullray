"""Merge overlapping [start, end] intervals. Tests capture the edge cases."""

def merge(intervals):
    out = []
    for iv in sorted(intervals):
        if out and iv[0] < out[-1][1]:
            if iv[1] > out[-1][1]:
                out[-1][1] = iv[1]
        else:
            out.append(list(iv))
    return [tuple(x) for x in out]
