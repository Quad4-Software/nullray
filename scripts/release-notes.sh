#!/usr/bin/env bash
# Build goreleaser-style release notes with linked short commits and sha256 table.
set -euo pipefail

TAG="${1:?tag required}"
REPO="${2:?owner/name required}"
OUT="${3:?output path required}"
BASE_URL="https://github.com/${REPO}"

prev="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
range="${TAG}"
if [[ -n "${prev}" ]]; then
  range="${prev}..${TAG}"
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
    # Escape markdown table-breaking pipes in subject
    msg="${msg//|/\\|}"
    echo "- [\`${short}\`](${BASE_URL}/commit/${sha}) ${msg}"
  done < <(git log --pretty=format:'%H %s' "${range}")
  echo
  echo "### Checksums"
  echo
  echo "| artifact | sha256 |"
  echo "|----------|--------|"
  if [[ -f dist/checksums.txt ]]; then
    while read -r sum file; do
      base="$(basename "${file}")"
      echo "| \`${base}\` | \`${sum}\` |"
    done < dist/checksums.txt
  else
    echo "| _(none)_ | |"
  fi
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
