#!/bin/sh
# nullray installer
#
#   curl -fsSL https://nullray.xyz/install | sh
#
# Optional env:
#   NULLRAY_VERSION      release tag like v1.2.3 (default: latest)
#   NULLRAY_PREFIX       install root (default: ~/.local)
#   NULLRAY_INSTALL_DIR  exact bin dir (overrides NULLRAY_PREFIX)
#
# The script downloads the release archive and checksums.txt over HTTPS,
# verifies the sha256, installs the binary, then runs a smoke check.
# Release tags are immutable on the repo, so a published asset cannot be
# swapped after the fact.

set -eu

REPO="Quad4-Software/nullray"
API="https://api.github.com/repos/${REPO}"
DL="https://github.com/${REPO}/releases/download"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

fetch() {
	curl -fSsL --proto '=https' --proto-redir '=https' -o "$2" "$1" \
		|| die "download failed: $1"
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die "missing sha256sum or shasum"
	fi
}

case "${1:-}" in
	-h|--help)
		say "usage: sh install.sh"
		say "env: NULLRAY_VERSION NULLRAY_PREFIX NULLRAY_INSTALL_DIR"
		exit 0
		;;
esac

need curl
need tar
need awk
need uname
need mktemp

os=$(uname -s)
arch=$(uname -m)
case "$os" in
	Linux)
		case "$arch" in
			x86_64|amd64) artifact="linux_amd64" ;;
			*) die "no prebuilt nullray for linux/$arch; build from source: git clone https://github.com/${REPO} && make" ;;
		esac
		;;
	Darwin)
		case "$arch" in
			arm64|aarch64) artifact="darwin_arm64" ;;
			*) die "no prebuilt nullray for macos/$arch; build from source: git clone https://github.com/${REPO} && make" ;;
		esac
		;;
	*) die "unsupported os: $os" ;;
esac

tag=${NULLRAY_VERSION:-}
if [ -z "$tag" ]; then
	meta=$(curl -fSsL --proto '=https' --proto-redir '=https' "${API}/releases/latest") \
		|| die "could not query latest release"
	tag=$(printf '%s' "$meta" | sed -n 's/.*"tag_name"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | head -n1)
	[ -n "$tag" ] || die "could not resolve latest release tag"
fi
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' \
	|| die "unexpected tag format: $tag"

ver=${tag#v}
name="nullray_${ver}_${artifact}"
archive="${name}.tar.gz"

tmp=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT INT TERM

say "nullray $tag ($artifact)"
fetch "${DL}/${tag}/${archive}" "$tmp/$archive"
fetch "${DL}/${tag}/checksums.txt" "$tmp/checksums.txt"

expected=$(awk -v f="$archive" '{sub(/^\.\//,"",$2); if ($2==f) {print $1; exit}}' "$tmp/checksums.txt")
[ -n "$expected" ] || die "no checksum entry for $archive"
printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' \
	|| die "malformed checksum for $archive"

actual=$(sha256_of "$tmp/$archive")
[ "$actual" = "$expected" ] \
	|| die "checksum mismatch for $archive (expected $expected, got $actual)"
say "sha256 verified: $actual"

tar -xzf "$tmp/$archive" -C "$tmp" || die "extract failed"
[ -f "$tmp/$name" ] || die "archive did not contain $name"

dest=${NULLRAY_INSTALL_DIR:-"${NULLRAY_PREFIX:-$HOME/.local}/bin"}
mkdir -p "$dest" || die "cannot create $dest"
[ -w "$dest" ] || die "no write access to $dest; set NULLRAY_INSTALL_DIR or rerun with sudo"

install -m 0755 "$tmp/$name" "$dest/nullray" || die "install to $dest failed"

if "$dest/nullray" --version >/dev/null 2>&1; then
	say "installed: $("$dest/nullray" --version | head -n1)"
else
	die "installed to $dest/nullray but it failed to run; on Linux install libcurl (libcurl4)"
fi

case ":$PATH:" in
	*":$dest:"*) ;;
	*) say "note: $dest is not in PATH; add: export PATH=\"$dest:\$PATH\"" ;;
esac

say "run: nullray"
