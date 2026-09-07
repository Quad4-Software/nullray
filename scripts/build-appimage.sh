#!/usr/bin/env bash
# Build a type-2 AppImage (FUSE3 runtime) from a prebuilt nullray binary.
# Verifies pinned linuxdeploy / appimagetool / type2-runtime digests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-${ROOT}/bin/nullray}"
OUT_DIR="${2:-${ROOT}/dist}"
VERSION="${VERSION:-0.1.0}"
# Tooling arch (AppImage naming). Artifact arch matches release matrix.
TOOL_ARCH="${TOOL_ARCH:-x86_64}"
ARTIFACT_ARCH="${ARTIFACT_ARCH:-amd64}"

LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-${TOOL_ARCH}.AppImage"
LINUXDEPLOY_SHA256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage"
APPIMAGETOOL_SHA256="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0"
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${TOOL_ARCH}"
RUNTIME_SHA256="1cc49bcf1e2ccd593c379adb17c9f85a36d619088296504de95b1d06215aebbf"

if [[ ! -f "${BINARY}" ]]; then
	echo "missing binary: ${BINARY}" >&2
	exit 1
fi

TOOL_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
APPDIR="${STAGE}/AppDir"
trap 'rm -rf "${TOOL_DIR}" "${STAGE}"' EXIT

fetch_verify() {
	local url="$1" sha="$2" dest="$3"
	curl -fsSL -o "${dest}" "${url}"
	echo "${sha}  ${dest}" | sha256sum -c -
}

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

fetch_verify "${LINUXDEPLOY_URL}" "${LINUXDEPLOY_SHA256}" "${TOOL_DIR}/linuxdeploy.AppImage"
fetch_verify "${APPIMAGETOOL_URL}" "${APPIMAGETOOL_SHA256}" "${TOOL_DIR}/appimagetool.AppImage"
fetch_verify "${RUNTIME_URL}" "${RUNTIME_SHA256}" "${TOOL_DIR}/runtime"
chmod +x "${TOOL_DIR}/linuxdeploy.AppImage" "${TOOL_DIR}/appimagetool.AppImage"

# GitHub runners and many containers lack FUSE. Extract-and-run avoids mount.
export APPIMAGE_EXTRACT_AND_RUN=1
# Skip linuxdeploy strip on modern ELF (.relr.dyn) from recent glibc.
export NO_STRIP=true

# Populate AppDir with shared libs. Do not emit an AppImage here.
"${TOOL_DIR}/linuxdeploy.AppImage" \
	--appdir "${APPDIR}" \
	--executable "${APPDIR}/usr/bin/nullray" \
	--desktop-file "${APPDIR}/usr/share/applications/nullray.desktop" \
	--icon-file "${ICON_FILE}"

# linuxdeploy may replace AppRun with a symlink to the binary. Restore the TUI wrapper.
install -m 755 "${ROOT}/packaging/appimage/AppRun" "${APPDIR}/AppRun"

OUT_NAME="nullray_${VERSION}_linux_${ARTIFACT_ARCH}.AppImage"
ARCH="${TOOL_ARCH}" VERSION="${VERSION}" \
	"${TOOL_DIR}/appimagetool.AppImage" \
	--runtime-file "${TOOL_DIR}/runtime" \
	"${APPDIR}" \
	"${OUT_DIR}/${OUT_NAME}"

chmod +x "${OUT_DIR}/${OUT_NAME}"
echo "wrote ${OUT_DIR}/${OUT_NAME}"
