#!/usr/bin/env bash
# Shared AppImage tool resolve/fetch for slim and SDK pack scripts.
# shellcheck shell=bash

appimage_tools_root() {
	cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

appimage_tools_load_manifest() {
	local root manifest line key val
	root="$(appimage_tools_root)"
	manifest="${NULLRAY_APPIMAGE_MANIFEST:-${root}/packaging/appimage/tools.manifest}"
	if [[ ! -f "${manifest}" ]]; then
		echo "missing tools manifest: ${manifest}" >&2
		return 1
	fi
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -z "${line}" || "${line}" =~ ^# ]] && continue
		key="${line%%=*}"
		val="${line#*=}"
		printf -v "${key}" '%s' "${val}"
	done <"${manifest}"
	: "${LINUXDEPLOY_FILE:?}" "${LINUXDEPLOY_SHA256:?}" "${LINUXDEPLOY_URL:?}"
	: "${APPIMAGETOOL_FILE:?}" "${APPIMAGETOOL_SHA256:?}" "${APPIMAGETOOL_URL:?}"
	: "${RUNTIME_FILE:?}" "${RUNTIME_SHA256:?}" "${RUNTIME_URL:?}"
	TOOL_ARCH="${TOOL_ARCH:-x86_64}"
}

appimage_tools_verify() {
	local file="$1" sha="$2"
	echo "${sha}  ${file}" | sha256sum -c -
}

appimage_tools_fetch_one() {
	local url="$1" sha="$2" dest="$3"
	curl -fsSL -o "${dest}" "${url}"
	appimage_tools_verify "${dest}" "${sha}"
}

# Resolve tools into DEST. Reuses files when hashes match.
# Prefers NULLRAY_APPIMAGE_TOOLS when set, else files already in DEST, else download.
appimage_tools_ensure() {
	local dest="${1:?dest required}"
	local src=""
	appimage_tools_load_manifest

	mkdir -p "${dest}"

	if [[ -n "${NULLRAY_APPIMAGE_TOOLS:-}" && -d "${NULLRAY_APPIMAGE_TOOLS}" ]]; then
		src="${NULLRAY_APPIMAGE_TOOLS}"
	fi

	_appimage_tools_ensure_one() {
		local file="$1" sha="$2" url="$3"
		local from="" target="${dest}/${file}"
		if [[ -n "${src}" && -f "${src}/${file}" ]]; then
			from="${src}/${file}"
		elif [[ -f "${target}" ]]; then
			from="${target}"
		fi
		if [[ -n "${from}" ]]; then
			if ! appimage_tools_verify "${from}" "${sha}" >/dev/null 2>&1; then
				echo "hash mismatch for ${from}, refetching" >&2
				from=""
			fi
		fi
		if [[ -z "${from}" ]]; then
			echo "fetching ${file}" >&2
			appimage_tools_fetch_one "${url}" "${sha}" "${target}.partial"
			mv -f "${target}.partial" "${target}"
			from="${target}"
		elif [[ "${from}" != "${target}" ]]; then
			cp -f "${from}" "${target}"
			appimage_tools_verify "${target}" "${sha}" >/dev/null
		fi
		chmod +x "${target}" 2>/dev/null || true
	}

	_appimage_tools_ensure_one "${LINUXDEPLOY_FILE}" "${LINUXDEPLOY_SHA256}" "${LINUXDEPLOY_URL}"
	_appimage_tools_ensure_one "${APPIMAGETOOL_FILE}" "${APPIMAGETOOL_SHA256}" "${APPIMAGETOOL_URL}"
	_appimage_tools_ensure_one "${RUNTIME_FILE}" "${RUNTIME_SHA256}" "${RUNTIME_URL}"

	ln -sfn "${LINUXDEPLOY_FILE}" "${dest}/linuxdeploy.AppImage"
	ln -sfn "${APPIMAGETOOL_FILE}" "${dest}/appimagetool.AppImage"
	ln -sfn "${RUNTIME_FILE}" "${dest}/runtime"

	cp -f "$(appimage_tools_root)/packaging/appimage/tools.manifest" "${dest}/MANIFEST"
}
