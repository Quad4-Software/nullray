#!/usr/bin/env bash
# Smoke-test the SDK AppImage under /tmp: extract, rebuild, pack slim.
# Optional: NULLRAY_SDK_SMOKE_REPACK_SDK=1 also packs a second SDK AppImage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
SDK_IMAGE="${1:-}"
TMP="$(mktemp -d /tmp/nullray-sdk-XXXXXX)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

echo "sdk-smoke: work dir ${TMP}"

if [[ -z "${SDK_IMAGE}" ]]; then
	echo "sdk-smoke: building SDK AppImage"
	make -C "${ROOT}" appimage-sdk
	SDK_IMAGE="${ROOT}/dist/nullray-sdk_${VERSION}_linux_amd64.AppImage"
fi

if [[ ! -f "${SDK_IMAGE}" ]]; then
	echo "missing SDK image: ${SDK_IMAGE}" >&2
	exit 1
fi

chmod +x "${SDK_IMAGE}"
export APPIMAGE_EXTRACT_AND_RUN=1
export NULLRAY_SDK_ROOT="${TMP}"

echo "sdk-smoke: extract"
"${SDK_IMAGE}" --sdk-extract

[[ -x "${TMP}/odin/odin" ]] || {
	echo "extract missing odin" >&2
	exit 1
}
[[ -f "${TMP}/src/Makefile" ]] || {
	echo "extract missing src" >&2
	exit 1
}
[[ -f "${TMP}/appimage-tools/MANIFEST" ]] || {
	echo "extract missing appimage-tools" >&2
	exit 1
}

echo "sdk-smoke: rebuild nullray"
export PATH="${TMP}/odin:${TMP}/bin:${PATH}"
export LD_LIBRARY_PATH="${TMP}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
make -C "${TMP}/src" clean all
"${TMP}/src/bin/nullray" --self-test

echo "sdk-smoke: pack slim AppImage (offline tools)"
export NULLRAY_APPIMAGE_TOOLS="${TMP}/appimage-tools"
make -C "${TMP}/src" appimage
SLIM="$(echo "${TMP}/src/dist"/nullray_*_linux_amd64.AppImage)"
[[ -f "${SLIM}" ]] || {
	echo "slim AppImage missing" >&2
	exit 1
}
echo "sdk-smoke: slim ok (${SLIM})"

if [[ "${NULLRAY_SDK_SMOKE_REPACK_SDK:-0}" == "1" ]]; then
	echo "sdk-smoke: pack SDK AppImage (offline tools)"
	export NULLRAY_ODIN_ROOT="${TMP}/odin"
	make -C "${TMP}/src" appimage-sdk
	NEW_SDK="$(echo "${TMP}/src/dist"/nullray-sdk_*_linux_amd64.AppImage)"
	[[ -f "${NEW_SDK}" ]] || {
		echo "repacked SDK missing" >&2
		exit 1
	}
	echo "sdk-smoke: sdk repack ok (${NEW_SDK})"
fi

echo "sdk-smoke: pass"
