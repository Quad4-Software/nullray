#!/usr/bin/env bash
# Measure stripped binary size and self-test peak RSS. Fail if over gates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/bin/nullray}"
MAX_BYTES="${NULLRAY_MAX_BINARY_BYTES:-4500000}"
MAX_RSS_KB="${NULLRAY_MAX_RSS_KB:-65536}"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

# Size gate matches release/AppImage claims (stripped). Keep the built binary intact.
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
