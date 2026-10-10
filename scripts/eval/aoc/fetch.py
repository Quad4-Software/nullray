#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
"""Build Advent of Code 2025 task dirs for scripts/eval/eval.py.

Sources (see README.md in this directory):
  - puzzle inputs + reference solutions: a public AoC 2025 repo
  - puzzle statements (both parts): a repo that mirrors day READMEs
  - gold answers: harvested by running the reference solutions locally

Generated task dirs go to ../tasks/aoc-dNN/ and are gitignored. Inputs and
statements are fetched per user and never committed (AoC asks that inputs
not be redistributed).

Usage:
    fetch.py [--days 1-12] [--input-repo OWNER/REPO]
             [--statements-repo OWNER/REPO] [--session COOKIE] [--force]

With --session (AoC session cookie), inputs come from the user's own
adventofcode.com account instead of the reference repo; answers are still
harvested by running the reference implementation on that input.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TASKS_DIR = HERE.parent / "tasks"

DEFAULT_INPUT_REPO = "nouhailaaziki/Advent-of-Code-2025"
DEFAULT_STMT_REPO = "SolunarNexus/adventofcode2025"
YEAR = 2025
REF_TIMEOUT = 180

# statements repo directory slugs per day
DAY_SLUGS = {
    1: "day-01-secret-entrance",
    2: "day-02-gift-shop",
    3: "day-03-lobby",
    4: "day-04-printing-department",
    5: "day-05-cafeteria",
    6: "day-06-trash-compactor",
    7: "day-07-laboratories",
    8: "day-08-playground",
    9: "day-09-movie-theatre",
    10: "day-10-factory",
    11: "day-11-reactor",
    12: "day-12-tree-farm",
}

# AoC 2025 day 12 ships a single part.
SINGLE_PART = {12}

DAY_TITLES = {
    1: "Secret Entrance",
    2: "Gift Shop",
    3: "Lobby",
    4: "Printing Department",
    5: "Cafeteria",
    6: "Trash Compactor",
    7: "Laboratories",
    8: "Playground",
    9: "Movie Theatre",
    10: "Factory",
    11: "Reactor",
    12: "Tree Farm",
}


def fetch(url: str, headers: dict | None = None) -> bytes:
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", "nullray-eval-fetch")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def raw_url(repo: str, path: str) -> str:
    return f"https://raw.githubusercontent.com/{repo}/main/{path}"


def fetch_input_aoc(day: int, session: str) -> bytes:
    return fetch(
        f"https://adventofcode.com/{YEAR}/day/{day}/input",
        {"Cookie": f"session={session}"},
    )


def fix_py2_prints(src: str) -> str:
    """Convert bare `print expr` statements to calls. Ref repo day01/part1
    is Python 2; the rest is Python 3."""
    return re.sub(r"(?m)^(\s*)print\s+([^(].*)$", r"\1print(\2)", src)


def harvest_answer(part_src: str, input_bytes: bytes, workdir: Path) -> str:
    """Run a reference partN.py inside workdir with puzzle_input present.
    Try argv path first, then stdin, then bare. Answer = last non-empty
    stdout line."""
    (workdir / "puzzle_input").write_bytes(input_bytes)
    (workdir / "part.py").write_text(fix_py2_prints(part_src), encoding="utf-8")
    stdin_text = input_bytes.decode("utf-8", "replace")
    # stdin feed first: most reference parts read sys.stdin and would eat an
    # inherited/empty stdin during an argv attempt, producing a bogus 0.
    attempts = [
        (["python3", "part.py"], stdin_text),
        (["python3", "part.py", "puzzle_input"], ""),
        (["python3", "part.py"], ""),
    ]
    last_err = ""
    for argv, stdin_data in attempts:
        try:
            proc = subprocess.run(
                argv, cwd=workdir, capture_output=True, text=True,
                timeout=REF_TIMEOUT, input=stdin_data,
            )
        except subprocess.TimeoutExpired:
            last_err = "timeout"
            continue
        if proc.returncode == 0:
            lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
            if lines:
                return lines[-1]
        last_err = (proc.stderr or proc.stdout).strip().splitlines()[-1] if (proc.stderr or proc.stdout).strip() else f"exit {proc.returncode}"
    # One more pass with third-party deps provided by uv (shapely on day 9,
    # pulp on day 10).
    try:
        proc = subprocess.run(
            ["uv", "run", "--quiet", "--with", "shapely", "--with", "pulp==3.2.2", "part.py"],
            cwd=workdir, capture_output=True, text=True,
            timeout=REF_TIMEOUT, input=stdin_text,
        )
        if proc.returncode == 0:
            lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
            if lines:
                return lines[-1]
        if (proc.stderr or "").strip():
            last_err = proc.stderr.strip().splitlines()[-1]
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        last_err = str(e)
    raise RuntimeError(f"reference solution failed: {last_err}")


def build_prompt(day: int, title: str, parts: int) -> str:
    if parts == 1:
        tail = "prints the answer on its own line."
    else:
        tail = "prints the Part 1 answer on one line, then the Part 2 answer on the next line."
    return (
        f"This is Advent of Code {YEAR} day {day} ({title}). The workspace "
        f"has input.txt (the puzzle input) and PROBLEM.md (the full puzzle "
        f"statement). Write solve.py (Python 3, stdlib only) that reads "
        f"input.txt from the current directory and {tail} Run it and make "
        f"sure it finishes quickly enough. Keep solve.py as the only "
        f"deliverable; do not commit anything."
    )


def build_verify(answers: list[str]) -> str:
    """Check each expected answer appears as a whole line of solve.py output.
    Answers live only in the verify command; the model never sees task.json."""
    pats = " && ".join(
        f"echo \"$OUT\" | grep -Fqx -- {json.dumps(a)}" for a in answers
    )
    run = (
        "OUT=$(timeout 120 python3 solve.py 2>/dev/null || "
        "timeout 120 python3 solve.py input.txt 2>/dev/null || "
        "timeout 120 python3 solve.py < input.txt 2>/dev/null); "
    )
    return run + pats


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", default="1-12")
    ap.add_argument("--input-repo", default=DEFAULT_INPUT_REPO)
    ap.add_argument("--statements-repo", default=DEFAULT_STMT_REPO)
    ap.add_argument("--session", default="")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if "-" in args.days:
        lo, hi = args.days.split("-", 1)
        days = list(range(int(lo), int(hi) + 1))
    else:
        days = [int(d) for d in args.days.split(",")]

    session = args.session or os_environ_session()
    input_src = "adventofcode.com (session)" if session else f"github:{args.input_repo}"
    print(f"inputs: {input_src}; statements: github:{args.statements_repo}")

    answers_table: dict[str, list[str]] = {}
    for day in days:
        dtag = f"day{day:02d}"
        task_id = f"aoc-d{day:02d}"
        tdir = TASKS_DIR / task_id
        if tdir.exists() and not args.force:
            print(f"{task_id}: exists, skipping (use --force)")
            continue
        tdir.mkdir(parents=True, exist_ok=True)
        (tdir / "seed").mkdir(exist_ok=True)

        # --- input ---
        if session:
            input_bytes = fetch_input_aoc(day, session)
        else:
            input_bytes = fetch(raw_url(args.input_repo, f"{dtag}/puzzle_input"))
        if len(input_bytes) < 8:
            print(f"{task_id}: input suspiciously small, check source")
        (tdir / "seed" / "input.txt").write_bytes(input_bytes)

        # --- statement ---
        try:
            stmt = fetch(raw_url(args.statements_repo, f"{DAY_SLUGS[day]}/README.md"))
            (tdir / "seed" / "PROBLEM.md").write_bytes(stmt)
        except Exception as e:
            print(f"{task_id}: no statement ({e}); prompt will rely on input only")

        # --- gold answers via reference solutions ---
        nparts = 1 if day in SINGLE_PART else 2
        answers = []
        for pnum in range(1, nparts + 1):
            src = fetch(raw_url(args.input_repo, f"{dtag}/part{pnum}.py")).decode("utf-8", "replace")
            with tempfile.TemporaryDirectory() as td:
                ans = harvest_answer(src, input_bytes, Path(td))
            answers.append(ans)
            print(f"{task_id} part{pnum}: {ans}")
        answers_table[task_id] = answers

        task = {
            "id": task_id,
            "prompt": build_prompt(day, DAY_TITLES[day], nparts),
            "verify": build_verify(answers),
            "env": {"NULLRAY_PRINT_TIMEOUT": "1800", "NULLRAY_AGENT_STEPS": "60"},
            "budget_tokens": 1_500_000,
        }
        (tdir / "task.json").write_text(json.dumps(task, indent=2) + "\n", encoding="utf-8")
        print(f"{task_id}: written")

    ap_file = HERE / "answers.json"
    # merge with existing answers so partial refetches do not clobber
    if ap_file.exists():
        old = json.loads(ap_file.read_text(encoding="utf-8"))
        old.update(answers_table)
        answers_table = old
    ap_file.write_text(json.dumps(answers_table, indent=2) + "\n", encoding="utf-8")
    print(f"answers: {ap_file} (gitignored, do not commit)")
    return 0


def os_environ_session() -> str:
    import os
    return os.environ.get("AOC_SESSION", "")


if __name__ == "__main__":
    raise SystemExit(main())
