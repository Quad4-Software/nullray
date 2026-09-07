#!/usr/bin/env bash
# Stage a prebuilt binary into packaging/flatpak and build a .flatpak bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-${ROOT}/bin/nullray}"
OUT_DIR="${2:-${ROOT}/dist}"
VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-x86_64}"
MANIFEST_DIR="${ROOT}/packaging/flatpak"
APP_ID="xyz.nullray"
BUNDLE="${OUT_DIR}/nullray_${VERSION}_linux_amd64.flatpak"

if [[ ! -f "${BINARY}" ]]; then
	echo "missing binary: ${BINARY}" >&2
	exit 1
fi

if ! command -v flatpak-builder >/dev/null 2>&1; then
	echo "flatpak-builder is required" >&2
	exit 1
fi

mkdir -p "${OUT_DIR}"
install -m 755 "${BINARY}" "${MANIFEST_DIR}/nullray"
install -m 644 "${ROOT}/logo/nullray.svg" "${MANIFEST_DIR}/nullray.svg"

BUILD_DIR="${OUT_DIR}/.flatpak-build"
REPO_DIR="${OUT_DIR}/.flatpak-repo"
rm -rf "${BUILD_DIR}" "${REPO_DIR}"

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

flatpak-builder \
	--user \
	--force-clean \
	--install-deps-from=flathub \
	--repo="${REPO_DIR}" \
	--arch="${ARCH}" \
	"${BUILD_DIR}" \
	"${MANIFEST_DIR}/${APP_ID}.yml"

flatpak build-bundle \
	--arch="${ARCH}" \
	"${REPO_DIR}" \
	"${BUNDLE}" \
	"${APP_ID}" \
	master

echo "wrote ${BUNDLE}"
