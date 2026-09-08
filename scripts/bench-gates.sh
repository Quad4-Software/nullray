#!/usr/bin/env bash
# Measure binary size and self-test peak RSS. Fail if over gates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/bin/nullray}"
MAX_BYTES="${NULLRAY_MAX_BINARY_BYTES:-4000000}"
MAX_RSS_KB="${NULLRAY_MAX_RSS_KB:-65536}"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

size="$(wc -c <"$BIN" | tr -d ' ')"
echo "binary_bytes=$size max=$MAX_BYTES"
if (( size > MAX_BYTES )); then
  echo "binary size gate failed" >&2
  exit 1
fi

rss_kb="$(
  python3 - "$BIN" <<'PY'
import resource, subprocess, sys, platform
bin_path = sys.argv[1]
subprocess.run([bin_path, "--self-test"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ru = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
if platform.system() == "Darwin":
    ru = ru // 1024
print(int(ru))
PY
)"

echo "selftest_rss_kb=$rss_kb max=$MAX_RSS_KB"
if (( rss_kb > MAX_RSS_KB )); then
  echo "rss gate failed" >&2
  exit 1
fi

echo "bench gates ok"
