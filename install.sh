#!/bin/sh
# nullray installer
#
#   curl -fsSL https://nullray.xyz/install | sh
#
# Clones the git repo, builds from source, and installs the binary.
# Re-run to pull and rebuild. The checkout stays so you can compile
# again later.
#
# Optional env:
#   NULLRAY_REPO         git URL (default: https://github.com/Quad4-Software/nullray.git)
#   NULLRAY_REF          branch or tag (default: master)
#   NULLRAY_SRC_DIR      clone path (default: ~/.local/src/nullray)
#   NULLRAY_PREFIX       install root (default: ~/.local)
#   NULLRAY_INSTALL_DIR  exact bin dir (overrides PREFIX/bin)

set -eu

REPO_DEFAULT="https://github.com/Quad4-Software/nullray.git"

say() { printf '%s\n' "$*"; }
warn() { printf 'install: warning: %s\n' "$*" >&2; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
	-h|--help)
		say "usage: sh install.sh"
		say "env: NULLRAY_REPO NULLRAY_REF NULLRAY_SRC_DIR NULLRAY_PREFIX NULLRAY_INSTALL_DIR"
		exit 0
		;;
esac

os=$(uname -s 2>/dev/null || echo unknown)
case "$os" in
	Linux|Darwin) ;;
	MINGW*|MSYS*|CYGWIN*|Windows_NT)
		# Makefile uses .exe and winsock when OS=Windows_NT.
		OS=Windows_NT
		export OS
		;;
	*)
		warn "unrecognized os '$os'. Linux, macOS, and Windows (Git Bash) are supported."
		;;
esac

missing=0

if command -v git >/dev/null 2>&1; then
	:
else
	warn "git is not installed. Install git, then rerun."
	case "$os" in
		Darwin) warn "macOS: xcode-select --install" ;;
		Linux) warn "Linux: install the git package from your distro" ;;
		MINGW*|MSYS*|CYGWIN*|Windows_NT) warn "Windows: https://git-scm.com/download/win" ;;
	esac
	missing=1
fi

if command -v odin >/dev/null 2>&1; then
	:
else
	warn "odin is not installed. Install the Odin compiler, then rerun."
	warn "https://github.com/odin-lang/Odin"
	case "$os" in
		Darwin) warn "macOS: clone Odin and run ./build_odin.sh (needs Xcode CLT / LLVM)" ;;
		Linux) warn "Linux: clone Odin and run ./build_odin.sh (needs clang/llvm and a linker)" ;;
		MINGW*|MSYS*|CYGWIN*|Windows_NT) warn "Windows: use an Odin release zip and put odin.exe on PATH" ;;
	esac
	missing=1
fi

if command -v make >/dev/null 2>&1; then
	:
else
	warn "make is not installed. The build uses the project Makefile."
	case "$os" in
		Darwin) warn "macOS: xcode-select --install" ;;
		Linux) warn "Linux: install make (often via build-essential or base-devel)" ;;
		MINGW*|MSYS*|CYGWIN*|Windows_NT) warn "Windows: install make (MSYS2, choco install make, or Git Bash extra tools)" ;;
	esac
	missing=1
fi

if command -v cc >/dev/null 2>&1; then
	:
elif command -v clang >/dev/null 2>&1; then
	CC=clang
	export CC
elif command -v gcc >/dev/null 2>&1; then
	CC=gcc
	export CC
else
	warn "no C compiler found (cc, clang, or gcc). Vendored TLS needs one."
	case "$os" in
		Darwin) warn "macOS: xcode-select --install" ;;
		Linux) warn "Linux: install a C compiler (build-essential, base-devel, or clang)" ;;
		MINGW*|MSYS*|CYGWIN*|Windows_NT) warn "Windows: install LLVM or MinGW and put clang/gcc on PATH" ;;
	esac
	missing=1
fi

if [ "$missing" -ne 0 ]; then
	die "missing required tools. Install them, then rerun."
fi

repo=${NULLRAY_REPO:-$REPO_DEFAULT}
ref=${NULLRAY_REF:-master}
src=${NULLRAY_SRC_DIR:-"${HOME}/.local/src/nullray"}
prefix=${NULLRAY_PREFIX:-"${HOME}/.local"}
dest=${NULLRAY_INSTALL_DIR:-"${prefix}/bin"}

# Prefer the checkout that contains this script, or the current directory.
script_dir=
if [ -n "${0:-}" ] && [ "$0" != "sh" ] && [ "$0" != "-" ] && [ "$0" != "-sh" ]; then
	script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
fi
if [ -n "$script_dir" ] && [ -f "$script_dir/Makefile" ] && [ -d "$script_dir/cmd/nullray" ]; then
	src=$script_dir
	say "building existing checkout: $src"
elif [ -f Makefile ] && [ -d cmd/nullray ] && [ -d nullray ]; then
	src=$(pwd)
	say "building current directory: $src"
elif [ -d "$src/.git" ]; then
	say "updating $src ($ref)"
	git -C "$src" fetch origin "$ref" || die "git fetch failed"
	git -C "$src" checkout "$ref" || die "git checkout $ref failed"
	if ! git -C "$src" merge --ff-only FETCH_HEAD; then
		warn "could not fast-forward $ref. building the current checkout."
	fi
elif [ -e "$src" ]; then
	die "$src exists and is not a git checkout. set NULLRAY_SRC_DIR to a new path"
else
	parent=$(dirname -- "$src")
	mkdir -p "$parent" || die "cannot create $parent"
	say "cloning $repo ($ref) into $src"
	git clone --branch "$ref" "$repo" "$src" \
		|| die "git clone failed"
fi

[ -f "$src/Makefile" ] || die "no Makefile in $src"
[ -d "$src/cmd/nullray" ] || die "no cmd/nullray in $src"

say "building in $src"
make -C "$src" || die "make failed"

mkdir -p "$dest" || die "cannot create $dest"
[ -w "$dest" ] || die "no write access to $dest. set NULLRAY_INSTALL_DIR or NULLRAY_PREFIX"

say "installing to $prefix (bin: $dest)"
make -C "$src" install PREFIX="$prefix" || die "make install failed"

bin="$dest/nullray"
if [ -f "$dest/nullray.exe" ]; then
	bin="$dest/nullray.exe"
fi
if [ "$dest" != "${prefix}/bin" ]; then
	if [ -f "$src/bin/nullray.exe" ]; then
		install -m 0755 "$src/bin/nullray.exe" "$dest/nullray.exe" || \
			cp "$src/bin/nullray.exe" "$dest/nullray.exe"
		bin="$dest/nullray.exe"
	elif [ -f "$src/bin/nullray" ]; then
		install -m 0755 "$src/bin/nullray" "$dest/nullray" || \
			cp "$src/bin/nullray" "$dest/nullray"
		bin="$dest/nullray"
	fi
fi

if [ -x "$bin" ] && "$bin" --version >/dev/null 2>&1; then
	say "installed: $("$bin" --version | head -n1)"
else
	die "built, but $bin failed to run"
fi

case ":$PATH:" in
	*":$dest:"*) ;;
	*) say "note: $dest is not in PATH; add: export PATH=\"$dest:\$PATH\"" ;;
esac

say "source: $src"
say "update later: git -C $src pull && make -C $src install PREFIX=$prefix"
say "run: nullray"
