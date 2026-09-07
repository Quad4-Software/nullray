#!/usr/bin/env bash
# Forced rebuild twice with fixed stamps.
# Assert same embedded build stamps, matching --version output, and that
# both binaries pass --self-test.
# Odin codegen is not deterministic across runs (symbol/data layout shifts),
# so byte or size equality cannot be asserted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export NULLRAY_BUILD_DATE="${NULLRAY_BUILD_DATE:-1970-01-01}"
export NULLRAY_BUILD_TIME="${NULLRAY_BUILD_TIME:-00:00:00}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

OUT_PATH=bin/nullray.repro
TMP_A="$(mktemp)"
trap 'rm -f "$TMP_A" "$OUT_PATH"' EXIT

make_repro() {
  rm -f "$OUT_PATH"
  make \
    BUILD_DATE="$NULLRAY_BUILD_DATE" \
    BUILD_TIME="$NULLRAY_BUILD_TIME" \
    OUT="$OUT_PATH" >/dev/null
}

make_repro
cp -a "$OUT_PATH" "$TMP_A"
ver_a="$("$TMP_A" --version)"

make_repro
ver_b="$("$OUT_PATH" --version)"

echo "ver_a=$ver_a"
echo "ver_b=$ver_b"

if [[ "$ver_a" != "$ver_b" ]]; then
  echo "reproducibility check failed: --version differs" >&2
  exit 1
fi
if ! grep -q "$NULLRAY_BUILD_DATE" <<<"$ver_a"; then
  echo "reproducibility check failed: build date missing from --version" >&2
  exit 1
fi
if ! grep -q "$NULLRAY_BUILD_TIME" <<<"$ver_a"; then
  echo "reproducibility check failed: build time missing from --version" >&2
  exit 1
fi

"$TMP_A" --self-test >/dev/null
"$OUT_PATH" --self-test >/dev/null

echo "reproducibility ok"
