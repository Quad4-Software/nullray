# nullray eval driver

Run a model x task matrix against the real binary and score every run with an
external verifier, not the model's own claim. Inspired by the scaffold papers:
harness held constant, models compared on tokens per solved task.

## Layout

    tasks/<id>/task.json   {"id","prompt","verify","difficulty"}
    tasks/<id>/seed/       files copied into the run workspace first
    eval.py                the driver

## Run

    python3 scripts/eval/eval.py --list
    python3 scripts/eval/eval.py \
        --models deepseek-v4-flash,glm-5.3-flash,qwen3.8-flash \
        --budget 3 --timeout 420

Output: one line per run plus results.jsonl and a summary with tokens per
solved task. Runs stop when cumulative estimated spend crosses --budget.

Verify uses each task's own shell check (pytest, assertions, grep) run in the
run workspace. Exit 0 and a green verifier are different things, the table
prints the verifier verdict.

Cost comes from the catalog price table in eval.py (USD per MTok). Extend the
table or drop unknown models to keep numbers honest.
