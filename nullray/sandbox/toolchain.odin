// SPDX-License-Identifier: 0BSD
/*
Toolchain cache RW grants so go/cargo/npm can write outside the workspace.
*/

package sandbox

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

toolchain_enabled_from_env :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_TOOLCHAIN, context.temp_allocator)
	if !ok {
		return true
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "false", "off", "no", "disable", "disabled":
		return false
	}
	return true
}

/*
Append narrow RW dirs for language toolchains (create if missing).
Keeps module caches out of the workspace when Landlock is on.
*/
toolchain_append_rw_paths :: proc(out: ^[dynamic]string, allocator := context.allocator) {
	if out == nil || !toolchain_enabled_from_env() {
		return
	}
	home, _ := os.lookup_env("HOME", context.temp_allocator)
	cache_root := xdg_dir("XDG_CACHE_HOME", home, ".cache", context.temp_allocator)
	parents := []string{cache_root}

	candidates := make([dynamic]string, context.temp_allocator)

	if v, ok := os.lookup_env("GOMODCACHE", context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		append(&candidates, strings.trim_space(v))
	} else if p, ok := docs_join_dir(home, "go/pkg/mod"); ok {
		append(&candidates, p)
	}
	if v, ok := os.lookup_env("GOCACHE", context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		append(&candidates, strings.trim_space(v))
	} else if p, ok := docs_join_dir(cache_root, "go-build"); ok {
		append(&candidates, p)
	}
	if p, ok := docs_join_dir(home, "go/pkg"); ok {
		append(&candidates, p)
	}
	if cargo, ok := os.lookup_env("CARGO_HOME", context.temp_allocator); ok && len(cargo) > 0 {
		append(&candidates, cargo)
	} else if p, ok := docs_join_dir(home, ".cargo"); ok {
		append(&candidates, p)
	}
	if p, ok := docs_join_dir(cache_root, "npm"); ok {
		append(&candidates, p)
	}
	if p, ok := docs_join_dir(home, ".npm"); ok {
		append(&candidates, p)
	}

	for raw in candidates {
		toolchain_add_rw_dir(out, raw, home, parents, allocator)
	}
}

/*
Child env for run_shell: force absolute module/build caches under home/XDG.
Also pin TMPDIR/GOTMPDIR to the sandbox tmp so go never writes /tmp.
Caller owns the slice and each string. Nil means inherit current env.
*/
toolchain_shell_env :: proc(allocator := context.allocator) -> []string {
	if !toolchain_enabled_from_env() {
		return nil
	}
	home, _ := os.lookup_env("HOME", context.temp_allocator)
	cache_root := xdg_dir("XDG_CACHE_HOME", home, ".cache", context.temp_allocator)
	if !filepath.is_abs(cache_root) || cache_root == "/tmp" || strings.has_prefix(cache_root, "/tmp/") {
		if p, ok := docs_join_dir(home, ".cache"); ok {
			cache_root = p
		}
	}

	gomod := toolchain_abs_cache_path("GOMODCACHE", home, "go/pkg/mod")
	gocache := ""
	if v, ok := os.lookup_env("GOCACHE", context.temp_allocator); ok {
		cand := strings.trim_space(v)
		if toolchain_cache_path_ok(cand, home) {
			gocache = cand
		}
	}
	if len(gocache) == 0 {
		if p, ok := docs_join_dir(cache_root, "go-build"); ok {
			gocache = p
		}
	}
	gopath := toolchain_abs_cache_path("GOPATH", home, "go")

	tmp := ""
	if st := state(); st != nil && len(st.tmp_dir) > 0 {
		tmp = st.tmp_dir
	} else {
		tmp = resolve_tmp_dir(context.temp_allocator)
	}

	if len(gomod) > 0 {
		_ = os.make_directory_all(gomod)
	}
	if len(gocache) > 0 {
		_ = os.make_directory_all(gocache)
	}
	if len(gopath) > 0 {
		_ = os.make_directory_all(gopath)
	}
	if len(tmp) > 0 {
		_ = os.make_directory_all(tmp)
	}

	base, err := os.environ(context.temp_allocator)
	if err != nil {
		base = nil
	}
	out := make([dynamic]string, allocator)
	for e in base {
		if strings.has_prefix(e, "GOMODCACHE=") ||
		   strings.has_prefix(e, "GOCACHE=") ||
		   strings.has_prefix(e, "GOPATH=") ||
		   strings.has_prefix(e, "GOTMPDIR=") ||
		   strings.has_prefix(e, "TMPDIR=") {
			continue
		}
		append(&out, strings.clone(e, allocator))
	}
	if len(gomod) > 0 {
		append(&out, fmt_env_pair("GOMODCACHE", gomod, allocator))
	}
	if len(gocache) > 0 {
		append(&out, fmt_env_pair("GOCACHE", gocache, allocator))
	}
	if len(gopath) > 0 {
		append(&out, fmt_env_pair("GOPATH", gopath, allocator))
	}
	if len(tmp) > 0 {
		append(&out, fmt_env_pair("GOTMPDIR", tmp, allocator))
		append(&out, fmt_env_pair("TMPDIR", tmp, allocator))
	}
	return out[:]
}

@(private)
toolchain_cache_path_ok :: proc(path: string, home: string) -> bool {
	p := strings.trim_space(path)
	if len(p) == 0 || !filepath.is_abs(p) {
		return false
	}
	if p == "/tmp" || strings.has_prefix(p, "/tmp/") {
		return false
	}
	if strings.contains(p, "/.go-cache") || strings.has_suffix(p, "/.mod-cache") {
		return false
	}
	if len(home) > 0 {
		h, _ := filepath.clean(home, context.temp_allocator)
		clean, _ := filepath.clean(p, context.temp_allocator)
		if path_beneath(clean, h) {
			return true
		}
	}
	return false
}

@(private)
toolchain_abs_cache_path :: proc(env_key, home, rel: string) -> string {
	if v, ok := os.lookup_env(env_key, context.temp_allocator); ok {
		cand := strings.trim_space(v)
		if toolchain_cache_path_ok(cand, home) {
			return cand
		}
	}
	if p, ok := docs_join_dir(home, rel); ok {
		return p
	}
	return ""
}

toolchain_shell_env_destroy :: proc(env: []string) {
	for e in env {
		delete(e)
	}
	delete(env)
}

@(private)
toolchain_add_rw_dir :: proc(
	out: ^[dynamic]string,
	path: string,
	home: string,
	parents: []string,
	allocator := context.allocator,
) {
	p := strings.trim_space(path)
	if len(p) == 0 || !filepath.is_abs(p) {
		return
	}
	clean, _ := filepath.clean(p, context.temp_allocator)
	if !docs_grant_safe(clean, home, parents) {
		return
	}
	_ = os.make_directory_all(clean)
	info, err := os.lstat(clean, context.temp_allocator)
	if err != nil {
		return
	}
	if info.type == .Symlink || info.type != .Directory {
		return
	}
	append_unique_owned(out, strings.clone(clean, allocator))
}
