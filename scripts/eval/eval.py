#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
"""nullray eval driver: run a model x task matrix and score externally.

Usage:
    eval.py [--models m1,m2] [--tasks t1,t2] [--budget USD] [--timeout SEC]
            [--bin PATH] [--out DIR] [--list]

Each task lives in scripts/eval/tasks/<id>/:
    task.json  {"id", "prompt", "verify"}   verify is a shell command run in
                                            the run workspace (exit 0 = pass)
    seed/      optional files copied into the workspace before the run

Results land in <out>/<task>_<model>/ plus a results.jsonl rollup and a
summary table on stdout. Cost uses catalog prices (USD per MTok in/out) with
a per-model override in task.json "prices" or the PRICES_FILE env.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_BIN = REPO / "bin" / "nullray"
TASKS_DIR = HERE / "tasks"

# OpenCode Zen catalog prices, USD per MTok (prompt, completion).
# Unknown models fall back to None and report cost as unknown rather than zero.
PRICES = {
    "deepseek-v4-flash": (0.14, 0.28),
    "glm-5.3-flash": (0.15, 0.50),
    "qwen3.8-flash": (0.15, 0.47),
    "minimax-m2.5": (0.30, 1.20),
    "qwen3.5-plus": (0.20, 1.20),
    "kimi-k2.6": (0.95, 4.00),
    "claude-haiku-4-5": (1.00, 5.00),
}

USAGE_RE = re.compile(r"session=(\d+)/(\d+)/(\d+)")


def load_tasks(only: set[str] | None) -> list[dict]:
    tasks = []
    for d in sorted(TASKS_DIR.iterdir()):
        tj = d / "task.json"
        if not tj.is_file():
            continue
        t = json.loads(tj.read_text(encoding="utf-8"))
        t["dir"] = d
        if only is None or t["id"] in only:
            tasks.append(t)
    return tasks


def estimate_cost(model: str, tokens_in: int, tokens_out: int) -> float | None:
    p = PRICES.get(model)
    if p is None:
        return None
    return tokens_in / 1e6 * p[0] + tokens_out / 1e6 * p[1]


def run_one(nullray: str, task: dict, model: str, out_dir: Path, timeout: int) -> dict:
    ws = out_dir / f"{task['id']}_{model.replace('/', '_')}"
    if ws.exists():
        shutil.rmtree(ws)
    ws.mkdir(parents=True)
    seed = task["dir"] / "seed"
    if seed.is_dir():
        shutil.copytree(seed, ws, dirs_exist_ok=True)
    env = dict(os.environ)
    env.update(
        {
            "NULLRAY_USAGE_PERSIST": "1",
            "NULLRAY_VERIFY": "1",
            "NULLRAY_NOTIFY": "off",
            "NULLRAY_STRUCTURE": "0",
        }
    )
    env.update(task.get("env", {}))
    start = time.time()
    argv = [
        nullray,
        "--print",
        task["prompt"],
        "--model",
        model,
        "--perms",
        "yolo",
        "--auto",
        "--usage",
        "--workspace",
        str(ws),
    ]
    argv += ["--mode", task.get("mode", "edit")]
    import shlex

    argv += shlex.split(task.get("args", ""))
    proc = subprocess.run(
        argv,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    wall = round(time.time() - start)
    (ws / "out.txt").write_text(proc.stdout, encoding="utf-8")
    (ws / "err.txt").write_text(proc.stderr, encoding="utf-8")

    tok_in = tok_out = 0
    m = None
    for match in USAGE_RE.finditer(proc.stderr):
        m = match
    if m:
        tok_in, tok_out = int(m.group(1)), int(m.group(2))

    verify = task.get("verify", "")
    verdict = "no-check"
    if verify:
        chk = subprocess.run(
            ["bash", "-c", verify],
            cwd=ws,
            capture_output=True,
            text=True,
            timeout=120,
        )
        verdict = "pass" if chk.returncode == 0 else "fail"
    elif proc.returncode != 0:
        verdict = "fail"

    cost = estimate_cost(model, tok_in, tok_out)
    return {
        "task": task["id"],
        "model": model,
        "exit": proc.returncode,
        "verdict": verdict,
        "tokens_in": tok_in,
        "tokens_out": tok_out,
        "wall_s": wall,
        "cost_usd": cost,
        "dir": str(ws),
    }


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--models", default="deepseek-v4-flash,glm-5.3-flash")
    ap.add_argument("--tasks", default="")
    ap.add_argument("--budget", type=float, default=3.0)
    ap.add_argument("--timeout", type=int, default=420)
    ap.add_argument("--bin", default=str(DEFAULT_BIN))
    ap.add_argument("--out", default="")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    tasks = load_tasks(set(args.tasks.split(",")) if args.tasks else None)
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    if args.list:
        for t in tasks:
            print(f"{t['id']}: {t['prompt'][:70]}")
        return 0

    out_dir = Path(args.out) if args.out else Path(
        os.environ.get("NULLRAY_EVAL_OUT", f"/tmp/nullray-eval-{int(time.time())}")
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    spent = 0.0
    results = []
    print(f"{'task':<14}{'model':<22}{'verdict':<9}{'in':>8}{'out':>7}{'wall':>6}{'cost$':>8}")
    for task in tasks:
        for model in models:
            cost0 = estimate_cost(model, 1, 1)
            if spent + (cost0 or 0) * 200_000 > args.budget:
                print(f"budget ${args.budget} reached, stopping")
                break
            try:
                r = run_one(args.bin, task, model, out_dir, args.timeout)
            except subprocess.TimeoutExpired:
                r = {
                    "task": task["id"], "model": model, "exit": -1,
                    "verdict": "timeout", "tokens_in": 0, "tokens_out": 0,
                    "wall_s": args.timeout, "cost_usd": None, "dir": "",
                }
            results.append(r)
            if r["cost_usd"]:
                spent += r["cost_usd"]
            cost_s = f"{r['cost_usd']:.4f}" if r["cost_usd"] is not None else "?"
            print(
                f"{r['task']:<14}{r['model']:<22}{r['verdict']:<9}"
                f"{r['tokens_in']:>8}{r['tokens_out']:>7}{r['wall_s']:>6}{cost_s:>8}"
            )

    roll = out_dir / "results.jsonl"
    with roll.open("w", encoding="utf-8") as fh:
        for r in results:
            fh.write(json.dumps(r) + "\n")

    solved = sum(1 for r in results if r["verdict"] == "pass")
    toks = sum(r["tokens_in"] + r["tokens_out"] for r in results)
    print(f"\nsolved {solved}/{len(results)}  total tokens {toks}  est spend ${spent:.3f}")
    if solved:
        print(f"tokens per solved task: {toks // solved}")
    print(f"results: {roll}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
