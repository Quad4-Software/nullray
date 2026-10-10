// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Toolchain cache RW grants so go/cargo/npm can write outside the workspace.
*/

package sandbox

import "core:mem"
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
Append narrow RW dirs for language toolchains (create if missing) plus RO
exec dirs for installed binaries. Keeps module caches out of the workspace
when Landlock is on. out_ro may be nil when only the RW list is wanted.
*/
toolchain_append_rw_paths :: proc(out: ^[dynamic]string, out_ro: ^[dynamic]string, allocator := context.allocator) {
	if out == nil || !toolchain_enabled_from_env() {
		return
	}
	home, _ := os.lookup_env("HOME", context.temp_allocator)
	cache_root := xdg_dir("XDG_CACHE_HOME", home, ".cache", context.temp_allocator)
	data_root := xdg_dir("XDG_DATA_HOME", home, ".local/share", context.temp_allocator)
	parents := []string{cache_root, data_root}

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

	// uv: interpreters land in XDG_DATA_HOME/uv/python and workspace venvs
	// symlink back to them, so an ungranted store makes every venv python
	// fail with EACCES. Created when absent so a first uv run can populate.
	if v, ok := os.lookup_env("UV_CACHE_DIR", context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		toolchain_add_rw_dir(out, strings.trim_space(v), home, parents, allocator)
	} else if p, ok := docs_join_dir(cache_root, "uv"); ok {
		toolchain_add_rw_dir(out, p, home, parents, allocator)
	}
	uv_dirs := []string{"UV_PYTHON_INSTALL_DIR", "UV_TOOL_DIR"}
	for key in uv_dirs {
		if v, ok := os.lookup_env(key, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			toolchain_add_rw_dir(out, strings.trim_space(v), home, parents, allocator)
		}
	}
	if p, ok := docs_join_dir(data_root, "uv"); ok {
		toolchain_add_rw_dir(out, p, home, parents, allocator)
	}

	// uv tool and pipx shims land in ~/.local/bin by default. RW only when
	// a managed tool already lives there so other user binaries are not
	// opened up for a rewrite; a plain RO grant still lets them execute.
	if b, ok := docs_join_dir(home, ".local/bin"); ok {
		if docs_dir_has_named_bin(b, []string{"uv", "uvx", "pipx"}) {
			toolchain_add_rw_dir(out, b, home, parents, allocator)
		} else if out_ro != nil {
			docs_add_existing_dir(out_ro, b, home, parents, allocator)
		}
	}
	bin_dirs := []string{"UV_TOOL_BIN_DIR", "PIPX_BIN_DIR"}
	for key in bin_dirs {
		if v, ok := os.lookup_env(key, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			toolchain_add_rw_dir(out, strings.trim_space(v), home, parents, allocator)
		}
	}

	// Version managers, env tooling, and agent CLI data get a grant only
	// when installed: creating these roots would leave stray dirs behind.
	home_roots := []struct{key, rel: string}{
		{"PYENV_ROOT", ".pyenv"},
		{"ASDF_DATA_DIR", ".asdf"},
		{"NVM_DIR", ".nvm"},
		{"VOLTA_HOME", ".volta"},
		{"BUN_INSTALL", ".bun"},
		{"RYE_HOME", ".rye"},
		{"MAMBA_ROOT_PREFIX", ".micromamba"},
		{"", "miniconda3"},
		{"", "miniforge3"},
		{"", "anaconda3"},
	}
	for e in home_roots {
		toolchain_add_env_or(out, e.key, home, e.rel, home, parents, allocator)
	}
	data_roots := []struct{key, rel: string}{
		{"MISE_DATA_DIR", "mise"},
		{"PNPM_HOME", "pnpm"},
		{"PIPX_HOME", "pipx"},
		{"", "virtualenvs"},
	}
	for e in data_roots {
		toolchain_add_env_or(out, e.key, data_root, e.rel, home, parents, allocator)
	}
	cache_roots := []struct{key, rel: string}{
		{"MISE_CACHE_DIR", "mise"},
		{"DENO_DIR", "deno"},
		{"", "pip"},
		{"", "pypoetry"},
	}
	for e in cache_roots {
		toolchain_add_env_or(out, e.key, cache_root, e.rel, home, parents, allocator)
	}

	// opencode: the harness preset resolves ~/.opencode/bin/opencode (RO is
	// enough to exec) while the CLI writes to its data, state, cache, and
	// config dirs. The writable roots are only created when the install
	// dir is present so machines without opencode stay clean.
	if p, ok := docs_join_dir(home, ".opencode"); ok {
		if info, err := os.lstat(p, context.temp_allocator); err == nil && info.type == .Directory {
			if out_ro != nil {
				docs_add_existing_dir(out_ro, p, home, parents, allocator)
			}
			if d, dok := docs_join_dir(data_root, "opencode"); dok {
				toolchain_add_rw_dir(out, d, home, parents, allocator)
			}
			if v, ok := os.lookup_env("XDG_STATE_HOME", context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
				if d, dok := docs_join_dir(strings.trim_space(v), "opencode"); dok {
					toolchain_add_rw_dir(out, d, home, parents, allocator)
				}
			} else if d, dok := docs_join_dir(home, ".local/state/opencode"); dok {
				toolchain_add_rw_dir(out, d, home, parents, allocator)
			}
			if d, dok := docs_join_dir(cache_root, "opencode"); dok {
				toolchain_add_rw_dir(out, d, home, parents, allocator)
			}
			if d, dok := docs_join_dir(home, ".config/opencode"); dok {
				toolchain_add_rw_dir(out, d, home, parents, allocator)
			}
		}
	}
}

/*
Grant env_key override when set, else root/rel. Exist-only: an absent tool
must not get a stray directory created under HOME.
*/
@(private)
toolchain_add_env_or :: proc(
	out: ^[dynamic]string,
	env_key: string,
	root: string,
	rel: string,
	home: string,
	parents: []string,
	allocator := context.allocator,
) {
	if len(env_key) > 0 {
		if v, ok := os.lookup_env(env_key, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			docs_add_existing_dir(out, strings.trim_space(v), home, parents, allocator)
			return
		}
	}
	if len(root) == 0 || len(rel) == 0 {
		return
	}
	if p, ok := docs_join_dir(root, rel); ok {
		docs_add_existing_dir(out, p, home, parents, allocator)
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
		   strings.has_prefix(e, "GIT_CONFIG_NOSYSTEM=") ||
		   strings.has_prefix(e, "GIT_CONFIG_GLOBAL=") ||
		   strings.has_prefix(e, "GIT_CONFIG_SYSTEM=") ||
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
	// Landlock blocks ~/.gitconfig and /etc/gitconfig, and git treats an
	// unreadable config as fatal ("unknown error occurred while reading
	// the configuration files"), so sandboxed children get config reads
	// disabled. Identity stays per-repo: shadow git sets local user.name
	// already, and user repos can set their own.
	if st := state(); st != nil && st.applied {
		append(&out, fmt_env_pair("GIT_CONFIG_NOSYSTEM", "1", allocator))
		append(&out, fmt_env_pair("GIT_CONFIG_GLOBAL", "/dev/null", allocator))
		append(&out, fmt_env_pair("GIT_CONFIG_SYSTEM", "/dev/null", allocator))
	}
	// Optional: export ask vault secrets into child env for scripts.
	if vault_export_enabled() {
		append_vault_env(&out, allocator)
	}
	return out[:]
}

vault_export_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_VAULT_EXPORT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes":
			return true
		}
	}
	return false
}

// Weak hook: packages that implement vault export register via this callback
// to avoid a sandbox->ask import cycle.
Vault_Export_Proc :: #type proc(dst: ^[dynamic]string, allocator: mem.Allocator) -> int
g_vault_export: Vault_Export_Proc

register_vault_export :: proc(cb: Vault_Export_Proc) {
	g_vault_export = cb
}

@(private)
append_vault_env :: proc(dst: ^[dynamic]string, allocator: mem.Allocator) {
	if g_vault_export != nil {
		_ = g_vault_export(dst, allocator)
	}
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
