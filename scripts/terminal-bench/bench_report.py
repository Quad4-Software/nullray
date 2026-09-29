#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
"""Summarize a Terminal-Bench run dir: resolved count and tokens per solved task.

Usage: bench_report.py <runs-dir-or-run-id-dir>

Reads tb results.json when present, falls back to scanning per-task dirs for
usage JSONL produced by the nullray adapter (NULLRAY_USAGE_PERSIST=1).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def iter_usage_records(run_dir: Path):
    for path in run_dir.rglob("*.jsonl"):
        if "usage" not in path.name and "usage" not in str(path.parent):
            continue
        try:
            rows = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for row in rows:
            try:
                rec = json.loads(row)
            except ValueError:
                continue
            if "prompt_tokens" in rec or "completion_tokens" in rec:
                yield rec


def count_resolved(run_dir: Path) -> tuple[int, int]:
    """Return (resolved, total) from tb results.json files if present."""
    resolved = 0
    total = 0
    for results in run_dir.rglob("results.json"):
        try:
            data = json.loads(results.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        rows = []
        if isinstance(data, dict):
            rows = data.get("results") or data.get("tasks") or []
        elif isinstance(data, list):
            rows = data
        for r in rows:
            if not isinstance(r, dict):
                continue
            total += 1
            if r.get("is_resolved") or r.get("resolved") or r.get("success"):
                resolved += 1
    return resolved, total


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    run_dir = Path(sys.argv[1])
    if not run_dir.is_dir():
        print(f"not a directory: {run_dir}")
        return 2

    total_in = 0
    total_out = 0
    for rec in iter_usage_records(run_dir):
        total_in += int(rec.get("prompt_tokens") or 0)
        total_out += int(rec.get("completion_tokens") or 0)

    resolved, total = count_resolved(run_dir)
    solved = resolved if resolved else 0
    denom = solved if solved else 1
    print(f"resolved: {resolved} / {total or 'unknown'}")
    print(f"prompt tokens: {total_in}")
    print(f"completion tokens: {total_out}")
    print(f"total tokens: {total_in + total_out}")
    print(f"tokens per solved task: {(total_in + total_out) // denom}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
