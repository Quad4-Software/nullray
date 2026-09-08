#!/usr/bin/env bash
# Clone and build the Odin commit in packaging/odin-pin.
# Usage: ensure-odin.sh [DEST]
# Default DEST: $HOME/Odin. Prints DEST on stdout when used with --print-path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${NULLRAY_ODIN_PIN:-${ROOT}/packaging/odin-pin}"
DEST="${HOME}/Odin"
PRINT_PATH=0

usage() {
	echo "usage: $0 [--print-path] [DEST]" >&2
	exit 2
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--print-path)
		PRINT_PATH=1
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		DEST="$1"
		shift
		;;
	esac
done

if [[ ! -f "${PIN_FILE}" ]]; then
	echo "missing odin pin: ${PIN_FILE}" >&2
	exit 1
fi

COMMIT="$(grep -E '^[0-9a-f]{40}$' "${PIN_FILE}" | head -n1 || true)"
if [[ -z "${COMMIT}" ]]; then
	echo "odin-pin must contain a full 40-char commit SHA" >&2
	exit 1
fi

need_build=1
if [[ -x "${DEST}/odin" && -d "${DEST}/.git" ]]; then
	actual="$(git -C "${DEST}" rev-parse HEAD 2>/dev/null || true)"
	if [[ "${actual}" == "${COMMIT}" ]]; then
		# Reject cross-arch cache restores (Exec format error).
		if "${DEST}/odin" version >/dev/null 2>&1; then
			need_build=0
			echo "odin already at ${COMMIT} in ${DEST}" >&2
		else
			echo "odin at ${COMMIT} in ${DEST} is not runnable, rebuilding" >&2
		fi
	fi
fi

if [[ "${need_build}" -eq 1 ]]; then
	echo "building odin ${COMMIT} in ${DEST}" >&2
	rm -rf "${DEST}"
	mkdir -p "${DEST}"
	git -C "${DEST}" init -q
	git -C "${DEST}" remote add origin https://github.com/odin-lang/Odin.git
	git -C "${DEST}" fetch --depth 1 origin "${COMMIT}"
	git -C "${DEST}" checkout -q FETCH_HEAD
	# Record expected pin even on shallow trees.
	echo "${COMMIT}" >"${DEST}/.nullray-odin-commit"
	(
		cd "${DEST}"
		./build_odin.sh
	)
	if [[ ! -x "${DEST}/odin" ]]; then
		echo "odin build failed: missing ${DEST}/odin" >&2
		exit 1
	fi
fi

echo "${COMMIT}" >"${DEST}/.nullray-odin-commit"
if [[ "${PRINT_PATH}" -eq 1 ]]; then
	echo "${DEST}"
fi
