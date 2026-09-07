#!/usr/bin/env bash
# Build a type-2 AppImage (FUSE3 runtime) from a prebuilt nullray binary.
# Uses NULLRAY_APPIMAGE_TOOLS when set (offline). Otherwise fetches pinned tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=appimage-tools.sh
source "${ROOT}/scripts/appimage-tools.sh"

BINARY="${1:-${ROOT}/bin/nullray}"
OUT_DIR="${2:-${ROOT}/dist}"
VERSION="${VERSION:-0.1.1}"
TOOL_ARCH="${TOOL_ARCH:-x86_64}"
ARTIFACT_ARCH="${ARTIFACT_ARCH:-amd64}"

if [[ ! -f "${BINARY}" ]]; then
	echo "missing binary: ${BINARY}" >&2
	exit 1
fi

TOOL_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
APPDIR="${STAGE}/AppDir"
trap 'rm -rf "${TOOL_DIR}" "${STAGE}"' EXIT

mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/share/applications" \
	"${APPDIR}/usr/share/icons/hicolor/scalable/apps" \
	"${OUT_DIR}"

install -m 755 "${BINARY}" "${APPDIR}/usr/bin/nullray"
install -m 755 "${ROOT}/packaging/appimage/AppRun" "${APPDIR}/AppRun"
install -m 644 "${ROOT}/packaging/appimage/nullray.desktop" \
	"${APPDIR}/usr/share/applications/nullray.desktop"
install -m 644 "${ROOT}/logo/nullray.svg" \
	"${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray.svg"

ICON_FILE="${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray.svg"
if command -v rsvg-convert >/dev/null 2>&1; then
	mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
	rsvg-convert -w 256 -h 256 "${ROOT}/logo/nullray.svg" \
		-o "${APPDIR}/usr/share/icons/hicolor/256x256/apps/nullray.png"
	ICON_FILE="${APPDIR}/usr/share/icons/hicolor/256x256/apps/nullray.png"
fi

appimage_tools_ensure "${TOOL_DIR}"

export APPIMAGE_EXTRACT_AND_RUN=1
export NO_STRIP=true

"${TOOL_DIR}/linuxdeploy.AppImage" \
	--appdir "${APPDIR}" \
	--executable "${APPDIR}/usr/bin/nullray" \
	--desktop-file "${APPDIR}/usr/share/applications/nullray.desktop" \
	--icon-file "${ICON_FILE}"

install -m 755 "${ROOT}/packaging/appimage/AppRun" "${APPDIR}/AppRun"

OUT_NAME="nullray_${VERSION}_linux_${ARTIFACT_ARCH}.AppImage"
ARCH="${TOOL_ARCH}" VERSION="${VERSION}" \
	"${TOOL_DIR}/appimagetool.AppImage" \
	--runtime-file "${TOOL_DIR}/runtime" \
	"${APPDIR}" \
	"${OUT_DIR}/${OUT_NAME}"

chmod +x "${OUT_DIR}/${OUT_NAME}"
echo "wrote ${OUT_DIR}/${OUT_NAME}"
