#!/usr/bin/env bash
# Validate a commit message file (or stdin) against the repo convention:
# Conventional Commits subject, <=72 chars, wrapped body.
set -euo pipefail

input="${1:-}"
if [[ -n "$input" ]]; then
  msg="$(cat -- "$input")"
else
  msg="$(cat)"
fi

subject="$(head -n1 <<<"$msg")"
types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

if ! [[ "$subject" =~ ^($types)(\([a-zA-Z0-9._/-]+\))?!?:[[:space:]][^[:space:]] ]]; then
  echo "commit-msg: subject must match 'type(scope): summary' ($types)" >&2
  exit 1
fi
if (( ${#subject} > 72 )); then
  echo "commit-msg: subject is ${#subject} chars, max 72" >&2
  exit 1
fi

fail=0
while IFS= read -r line; do
  if (( ${#line} > 80 )); then
    echo "commit-msg: body line over 80 chars: ${line:0:40}..." >&2
    fail=1
  fi
done < <(tail -n +3 <<<"$msg")
(( fail == 0 ))
