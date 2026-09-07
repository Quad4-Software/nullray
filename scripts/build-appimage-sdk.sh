#!/usr/bin/env bash
# Build the airgap SDK AppImage: nullray + Odin tree + source + pack tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=appimage-tools.sh
source "${ROOT}/scripts/appimage-tools.sh"

BINARY="${1:-${ROOT}/bin/nullray}"
OUT_DIR="${2:-${ROOT}/dist}"
VERSION="${VERSION:-0.1.1}"
TOOL_ARCH="${TOOL_ARCH:-x86_64}"
ARTIFACT_ARCH="${ARTIFACT_ARCH:-amd64}"
PIN_FILE="${NULLRAY_ODIN_PIN:-${ROOT}/packaging/odin-pin}"

if [[ ! -f "${BINARY}" ]]; then
	echo "missing binary: ${BINARY}" >&2
	exit 1
fi

ODIN_ROOT="${NULLRAY_ODIN_ROOT:-}"
if [[ -z "${ODIN_ROOT}" ]]; then
	if command -v odin >/dev/null 2>&1; then
		ODIN_ROOT="$(odin root 2>/dev/null || true)"
	fi
fi
if [[ -z "${ODIN_ROOT}" || ! -x "${ODIN_ROOT}/odin" ]]; then
	echo "set NULLRAY_ODIN_ROOT to an Odin tree with ./odin, or put odin on PATH" >&2
	exit 1
fi

ODIN_COMMIT="$(grep -E '^[0-9a-f]{40}$' "${PIN_FILE}" | head -n1 || true)"
if [[ -z "${ODIN_COMMIT}" ]]; then
	echo "missing commit in ${PIN_FILE}" >&2
	exit 1
fi
if [[ -f "${ODIN_ROOT}/.nullray-odin-commit" ]]; then
	bundled_commit="$(tr -d '[:space:]' <"${ODIN_ROOT}/.nullray-odin-commit")"
elif [[ -d "${ODIN_ROOT}/.git" ]]; then
	bundled_commit="$(git -C "${ODIN_ROOT}" rev-parse HEAD 2>/dev/null || true)"
else
	bundled_commit=""
fi
if [[ -n "${bundled_commit}" && "${bundled_commit}" != "${ODIN_COMMIT}" ]]; then
	echo "warning: Odin at ${ODIN_ROOT} is ${bundled_commit}, pin is ${ODIN_COMMIT}" >&2
fi

TOOL_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
APPDIR="${STAGE}/AppDir"
trap 'rm -rf "${TOOL_DIR}" "${STAGE}"' EXIT

mkdir -p \
	"${APPDIR}/usr/bin" \
	"${APPDIR}/usr/lib/odin" \
	"${APPDIR}/usr/share/applications" \
	"${APPDIR}/usr/share/icons/hicolor/scalable/apps" \
	"${APPDIR}/usr/share/nullray/src" \
	"${APPDIR}/usr/share/nullray/appimage-tools" \
	"${OUT_DIR}"

install -m 755 "${BINARY}" "${APPDIR}/usr/bin/nullray"
install -m 755 "${ROOT}/packaging/appimage/AppRun-sdk" "${APPDIR}/AppRun"
install -m 644 "${ROOT}/packaging/appimage/nullray-sdk.desktop" \
	"${APPDIR}/usr/share/applications/nullray-sdk.desktop"
install -m 644 "${ROOT}/logo/nullray.svg" \
	"${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray-sdk.svg"
# Alias icon name expected by some desktop tooling.
cp -f "${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray-sdk.svg" \
	"${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray.svg"

ICON_FILE="${APPDIR}/usr/share/icons/hicolor/scalable/apps/nullray-sdk.svg"
if command -v rsvg-convert >/dev/null 2>&1; then
	mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
	rsvg-convert -w 256 -h 256 "${ROOT}/logo/nullray.svg" \
		-o "${APPDIR}/usr/share/icons/hicolor/256x256/apps/nullray-sdk.png"
	ICON_FILE="${APPDIR}/usr/share/icons/hicolor/256x256/apps/nullray-sdk.png"
fi

echo "${VERSION}" >"${APPDIR}/usr/share/nullray/SDK_VERSION"
echo "${ODIN_COMMIT}" >"${APPDIR}/usr/share/nullray/ODIN_COMMIT"

# Odin compiler tree (binary + base/core/vendor).
if command -v rsync >/dev/null 2>&1; then
	rsync -a \
		--exclude '.git' \
		--exclude '*.o' \
		--exclude '*.obj' \
		"${ODIN_ROOT}/" "${APPDIR}/usr/lib/odin/"
else
	cp -a "${ODIN_ROOT}/." "${APPDIR}/usr/lib/odin/"
	rm -rf "${APPDIR}/usr/lib/odin/.git"
fi
chmod +x "${APPDIR}/usr/lib/odin/odin"
ln -sfn ../lib/odin/odin "${APPDIR}/usr/bin/odin"
echo "${ODIN_COMMIT}" >"${APPDIR}/usr/lib/odin/.nullray-odin-commit"

# nullray sources needed to make + pack.
SRC_DST="${APPDIR}/usr/share/nullray/src"
copy_tree() {
	local src="$1" dest="$2"
	mkdir -p "${dest}"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a --exclude '.git' "${src}/" "${dest}/"
	else
		cp -a "${src}/." "${dest}/"
		rm -rf "${dest}/.git"
	fi
}
copy_tree "${ROOT}/cmd" "${SRC_DST}/cmd"
copy_tree "${ROOT}/nullray" "${SRC_DST}/nullray"
copy_tree "${ROOT}/scripts" "${SRC_DST}/scripts"
copy_tree "${ROOT}/packaging" "${SRC_DST}/packaging"
copy_tree "${ROOT}/logo" "${SRC_DST}/logo"
cp -f "${ROOT}/Makefile" "${ROOT}/LICENSE" "${SRC_DST}/"

# Offline tool cache (also used while packing this image).
if [[ -n "${NULLRAY_APPIMAGE_TOOLS:-}" && -d "${NULLRAY_APPIMAGE_TOOLS}" ]]; then
	appimage_tools_ensure "${TOOL_DIR}"
else
	# Populate TOOL_DIR then copy into AppDir cache.
	appimage_tools_ensure "${TOOL_DIR}"
fi
cp -a "${TOOL_DIR}/." "${APPDIR}/usr/share/nullray/appimage-tools/"
# Drop temp symlinks noise is fine; ensure real files exist.
appimage_tools_ensure "${APPDIR}/usr/share/nullray/appimage-tools"

export APPIMAGE_EXTRACT_AND_RUN=1
export NO_STRIP=true

"${TOOL_DIR}/linuxdeploy.AppImage" \
	--appdir "${APPDIR}" \
	--executable "${APPDIR}/usr/bin/nullray" \
	--executable "${APPDIR}/usr/lib/odin/odin" \
	--desktop-file "${APPDIR}/usr/share/applications/nullray-sdk.desktop" \
	--icon-file "${ICON_FILE}"

# linuxdeploy may replace AppRun.
install -m 755 "${ROOT}/packaging/appimage/AppRun-sdk" "${APPDIR}/AppRun"

OUT_NAME="nullray-sdk_${VERSION}_linux_${ARTIFACT_ARCH}.AppImage"
ARCH="${TOOL_ARCH}" VERSION="${VERSION}" \
	"${TOOL_DIR}/appimagetool.AppImage" \
	--runtime-file "${TOOL_DIR}/runtime" \
	"${APPDIR}" \
	"${OUT_DIR}/${OUT_NAME}"

chmod +x "${OUT_DIR}/${OUT_NAME}"
echo "wrote ${OUT_DIR}/${OUT_NAME}"
