#!/usr/bin/env bash
# Provider-free print-mode CLI smoke. Exit 0 on success.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${NULLRAY_BIN:-}"
if [[ -z "$BIN" ]]; then
  if [[ -x "$ROOT/bin/nullray" ]]; then
    BIN="$ROOT/bin/nullray"
  elif [[ -x "$ROOT/bin/nullray.exe" ]]; then
    BIN="$ROOT/bin/nullray.exe"
  else
    echo "print-smoke: bin/nullray not found (build first)" >&2
    exit 1
  fi
fi

expect_exit() {
  local want="$1"
  shift
  set +e
  "$@" >/dev/null 2>&1
  local got=$?
  set -e
  if [[ "$got" -ne "$want" ]]; then
    echo "print-smoke: expected exit $want from: $* (got $got)" >&2
    exit 1
  fi
}

expect_exit 2 "$BIN" --print
expect_exit 2 "$BIN" --print --mode edit --perms ask "x"

help_out="$("$BIN" --help)"
echo "$help_out" | grep -q -- '--print'
echo "$help_out" | grep -q 'ask | plan | review | edit'

# Modes and flags parse without a TTY.
expect_exit 2 "$BIN" --print --bare --mode review --fail-on-findings
expect_exit 2 "$BIN" --print --mode plan --plan-out /tmp/nullray-print-smoke-plan.md
expect_exit 2 "$BIN" --print --output-format json --timeout 5

echo "print-smoke: ok ($BIN)"
