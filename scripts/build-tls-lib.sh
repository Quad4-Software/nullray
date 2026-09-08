#!/usr/bin/env bash
# Build lib/libnullray_tls.a from vendor/mbedtls (same recipe as Makefile tls-lib).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make tls-lib
