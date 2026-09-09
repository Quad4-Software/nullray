// SPDX-License-Identifier: 0BSD
/*
Host offline-docs RO paths for Landlock (tldr, rustup, non-system GOROOT).
*/

package sandbox

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

docs_enabled_from_env :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_DOCS, context.temp_allocator)
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
Append existing absolute docs cache/toolchain dirs to out (owned strings).
Never grants $HOME itself, HOME ancestors, symlinks, or sensitive basenames.
*/
docs_append_ro_paths :: proc(out: ^[dynamic]string, allocator := context.allocator) {
	if out == nil || !docs_enabled_from_env() {
		return
	}
	home, _ := os.lookup_env("HOME", context.temp_allocator)
	cache_root := xdg_dir("XDG_CACHE_HOME", home, ".cache", context.temp_allocator)
	data_root := xdg_dir("XDG_DATA_HOME", home, ".local/share", context.temp_allocator)
	parents := []string{cache_root, data_root}

	if p, ok := docs_join_dir(cache_root, "tealdeer"); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
	}
	if p, ok := docs_join_dir(data_root, "tealdeer"); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
	}
	if p, ok := docs_join_dir(home, ".tldr"); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
	}

	if rustup, ok := os.lookup_env("RUSTUP_HOME", context.temp_allocator); ok && len(rustup) > 0 {
		docs_add_existing_dir(out, rustup, home, parents, allocator)
	} else if p, ok := docs_join_dir(home, ".rustup"); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
	}
	if cargo, ok := os.lookup_env("CARGO_HOME", context.temp_allocator); ok && len(cargo) > 0 {
		if p, jok := docs_join_dir(cargo, "bin"); jok {
			docs_add_existing_dir(out, p, home, parents, allocator)
		}
	} else if p, ok := docs_join_dir(home, ".cargo/bin"); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
	}

	if goroot, ok := os.lookup_env("GOROOT", context.temp_allocator); ok && len(goroot) > 0 {
		if !docs_path_under_system(goroot) {
			docs_add_existing_dir(out, goroot, home, parents, allocator)
		}
	}

	local_bin, lok := docs_join_dir(home, ".local/bin")
	if lok && docs_dir_has_named_bin(local_bin, []string{"tldr", "rustup", "go", "ri"}) {
		docs_add_existing_dir(out, local_bin, home, parents, allocator)
	}
}

/*
Copy the process environment with secret-shaped keys removed.
Caller owns the returned slice and each string.
*/
docs_scrubbed_env :: proc(allocator := context.allocator) -> []string {
	base, err := os.environ(context.temp_allocator)
	if err != nil {
		base = nil
	}
	out := make([dynamic]string, allocator)
	for e in base {
		eq := strings.index_byte(e, '=')
		if eq <= 0 {
			continue
		}
		key := e[:eq]
		if docs_env_key_secret(key) {
			continue
		}
		append(&out, strings.clone(e, allocator))
	}
	return out[:]
}

/*
GOCACHE and GOTMPDIR under sandbox tmp so go doc need not write to ~/go.
Secret-shaped env keys are dropped from the child environment.
Caller owns the returned slice and each string.
*/
docs_go_child_env :: proc(allocator := context.allocator) -> []string {
	tmp := ""
	if st := state(); st != nil && len(st.tmp_dir) > 0 {
		tmp = st.tmp_dir
	} else {
		tmp = resolve_tmp_dir(context.temp_allocator)
	}
	gocache, gerr := filepath.join({tmp, "go-cache"}, context.temp_allocator)
	if gerr != nil {
		gocache = tmp
	}
	_ = os.make_directory_all(gocache)

	base := docs_scrubbed_env(allocator)
	out := make([dynamic]string, allocator)
	for e in base {
		if strings.has_prefix(e, "GOCACHE=") || strings.has_prefix(e, "GOTMPDIR=") {
			delete(e)
			continue
		}
		append(&out, e)
	}
	delete(base)
	append(&out, fmt_env_pair("GOCACHE", gocache, allocator))
	append(&out, fmt_env_pair("GOTMPDIR", tmp, allocator))
	return out[:]
}

docs_env_destroy :: proc(env: []string) {
	for e in env {
		delete(e)
	}
	delete(env)
}

@(private)
docs_env_key_secret :: proc(key: string) -> bool {
	upper := strings.to_upper(key, context.temp_allocator)
	markers := []string{"KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL", "AUTHORIZATION", "AUTH", "COOKIE", "PRIVATE"}
	for m in markers {
		if strings.contains(upper, m) {
			return true
		}
	}
	return false
}

@(private)
fmt_env_pair :: proc(key, value: string, allocator := context.allocator) -> string {
	return strings.concatenate({key, "=", value}, allocator)
}

@(private)
docs_join_dir :: proc(root, rel: string) -> (path: string, ok: bool) {
	if len(root) == 0 {
		return "", false
	}
	joined, jerr := filepath.join({root, rel}, context.temp_allocator)
	if jerr != nil {
		return "", false
	}
	return joined, true
}

@(private)
xdg_dir :: proc(env_key, home, rel: string, allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(env_key, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return strings.clone(strings.trim_space(v), allocator)
	}
	if len(home) == 0 {
		return strings.clone("/tmp", allocator)
	}
	joined, jerr := filepath.join({home, rel}, allocator)
	if jerr != nil {
		return strings.clone("/tmp", allocator)
	}
	return joined
}

@(private)
docs_add_existing_dir :: proc(
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
	info, err := os.lstat(clean, context.temp_allocator)
	if err != nil {
		return
	}
	if info.type == .Symlink {
		return
	}
	if info.type != .Directory {
		return
	}
	append_unique_owned(out, strings.clone(clean, allocator))
}

/*
Reject HOME itself, HOME ancestors, symlinks, sensitive leaves, and paths
outside HOME / XDG parents / system toolchain roots (use EXTRA_RO otherwise).
*/
docs_grant_safe :: proc(path: string, home: string, parents: []string = nil) -> bool {
	clean, _ := filepath.clean(path, context.temp_allocator)
	if len(clean) == 0 || clean == "/" {
		return false
	}
	base := filepath.base(clean)
	sensitive := []string{".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".netrc", ".config", "credentials", "Secrets"}
	for s in sensitive {
		if base == s {
			return false
		}
	}
	if len(home) > 0 {
		h, _ := filepath.clean(home, context.temp_allocator)
		if clean == h {
			return false
		}
		if path_beneath(h, clean) && clean != h {
			return false
		}
		if path_beneath(clean, h) {
			return true
		}
	}
	for parent in parents {
		if len(parent) == 0 {
			continue
		}
		proot, _ := filepath.clean(parent, context.temp_allocator)
		if proot == "/" || len(proot) < 2 {
			continue
		}
		if clean == proot {
			continue
		}
		if path_beneath(clean, proot) {
			return true
		}
	}
	system_roots := []string{"/usr", "/opt", "/var/lib", "/var/cache"}
	for root in system_roots {
		if clean == root || path_beneath(clean, root) {
			return true
		}
	}
	return false
}

@(private)
docs_path_under_system :: proc(path: string) -> bool {
	clean, _ := filepath.clean(path, context.temp_allocator)
	return strings.has_prefix(clean, "/usr/") || clean == "/usr" ||
		strings.has_prefix(clean, "/lib/") || clean == "/lib" ||
		strings.has_prefix(clean, "/lib64/") || clean == "/lib64"
}

@(private)
docs_dir_has_named_bin :: proc(dir: string, names: []string) -> bool {
	info, err := os.lstat(dir, context.temp_allocator)
	if err != nil || info.type != .Directory {
		return false
	}
	for name in names {
		cand, jerr := filepath.join({dir, name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if os.exists(cand) {
			return true
		}
	}
	return false
}
