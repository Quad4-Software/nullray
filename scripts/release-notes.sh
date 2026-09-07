#!/usr/bin/env bash
# Build release notes with linked commits and a sha256 table for every asset.
set -euo pipefail

TAG="${1:?tag required}"
REPO="${2:?owner/name required}"
OUT="${3:?output path required}"
DIST_DIR="${4:-dist}"
BASE_URL="https://github.com/${REPO}"

prev="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
range="${TAG}"
if [[ -n "${prev}" ]]; then
	range="${prev}..${TAG}"
fi

checksums="${DIST_DIR}/checksums.txt"
if [[ ! -f "${checksums}" ]]; then
	echo "missing ${checksums}" >&2
	exit 1
fi

{
	echo "## ${TAG}"
	echo
	if [[ -n "${prev}" ]]; then
		echo "Changes since [${prev}](${BASE_URL}/releases/tag/${prev})."
	else
		echo "Initial tagged release."
	fi
	echo
	echo "### Commits"
	echo
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		sha="${line%% *}"
		msg="${line#* }"
		short="${sha:0:7}"
		msg="${msg//|/\\|}"
		echo "- [\`${short}\`](${BASE_URL}/commit/${sha}) ${msg}"
	done < <(git log --pretty=format:'%H %s' "${range}")
	echo
	echo "### Binary assets (sha256)"
	echo
	echo "| artifact | sha256 |"
	echo "|----------|--------|"
	while read -r sum file; do
		base="$(basename "${file}")"
		case "${base}" in
			checksums.txt|notes.md) continue ;;
		esac
		echo "| \`${base}\` | \`${sum}\` |"
	done < "${checksums}"
	echo
	echo "Full list is also in \`checksums.txt\` on this release."
	echo
	echo "### Summary"
	echo
	count="$(git rev-list --count "${range}" 2>/dev/null || echo 0)"
	if [[ -n "${prev}" ]]; then
		echo "${count} commits from ${prev} to ${TAG}."
	else
		echo "${count} commits included in ${TAG}."
	fi
} >"${OUT}"

echo "wrote ${OUT}"
