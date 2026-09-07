#!/usr/bin/env bash
# Download and verify pinned AppImage pack tools into DEST (default: dist/appimage-tools).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=appimage-tools.sh
source "${ROOT}/scripts/appimage-tools.sh"

DEST="${1:-${ROOT}/dist/appimage-tools}"
appimage_tools_ensure "${DEST}"
echo "tools ready in ${DEST}"
