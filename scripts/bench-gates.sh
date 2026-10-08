#!/usr/bin/env bash
# Measure stripped binary size and self-test peak RSS. Fail if over gates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/bin/nullray}"
ODIN="${ODIN:-odin}"
# Room for session seal crypto + planner/strip/malleable UI growth.
MAX_BYTES="${NULLRAY_MAX_BINARY_BYTES:-7200000}"
MAX_RSS_KB="${NULLRAY_MAX_RSS_KB:-65536}"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

# Size gate matches the stripped-binary claim. Keep the built binary intact.
size_bin="$BIN"
strip_tmp=""
cleanup() {
  [[ -n "$strip_tmp" && -f "$strip_tmp" ]] && rm -f "$strip_tmp"
}
trap cleanup EXIT
if command -v strip >/dev/null 2>&1; then
  strip_tmp="$(mktemp "${TMPDIR:-/tmp}/nullray.stripped.XXXXXX")"
  strip -o "$strip_tmp" "$BIN"
  chmod +x "$strip_tmp"
  size_bin="$strip_tmp"
fi

size="$(wc -c <"$size_bin" | tr -d ' ')"
echo "binary_bytes=$size max=$MAX_BYTES"
if (( size > MAX_BYTES )); then
  echo "binary size gate failed" >&2
  exit 1
fi

# Peak RSS: Odin probe on Linux (no python/GNU time needed), BSD time -l
# elsewhere (macOS reports bytes).
case "$(uname -s)" in
Linux)
  rss_kb=$("$ODIN" run "$ROOT/scripts/rss_probe.odin" -file -- "$BIN" --self-test 2>/dev/null | tail -1)
  ;;
*)
  rss_kb=$(/usr/bin/time -l "$BIN" --self-test 2>&1 >/dev/null | awk '/maximum resident set size/{print int($1/1024)}')
  ;;
esac

echo "selftest_rss_kb=$rss_kb max=$MAX_RSS_KB"
if (( rss_kb > MAX_RSS_KB )); then
  echo "rss gate failed" >&2
  exit 1
fi

echo "bench gates ok"
