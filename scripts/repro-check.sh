#!/usr/bin/env bash
# Forced rebuild twice with fixed stamps.
# Assert same size, same embedded build stamps, and matching --version output.
# Full bit-identity is not required (linker/build-id and ASLR-related noise).
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
size_a="$(wc -c <"$TMP_A" | tr -d ' ')"
ver_a="$("$TMP_A" --version)"

make_repro
size_b="$(wc -c <"$OUT_PATH" | tr -d ' ')"
ver_b="$("$OUT_PATH" --version)"

echo "size_a=$size_a size_b=$size_b"
echo "ver_a=$ver_a"
echo "ver_b=$ver_b"

if [[ "$size_a" != "$size_b" ]]; then
  echo "reproducibility check failed: binary sizes differ" >&2
  exit 1
fi
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

echo "reproducibility ok"
