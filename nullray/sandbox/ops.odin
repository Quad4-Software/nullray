// SPDX-License-Identifier: 0BSD
/*
Ops profiles: desktop config RW, docker.sock, intentional kube access.
*/

package sandbox

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

/*
Apply NULLRAY_OPS CSV profiles onto cfg before Landlock apply.
Profiles: off|desktop|docker|kube|full (full = desktop+docker+kube).
Kube keeps KUBECONFIG only when secrets allow already covers kube paths.
*/
ops_apply_to_config :: proc(cfg: ^Config, allocator := context.allocator) {
	raw, ok := os.lookup_env(constants.ENV_OPS, context.temp_allocator)
	if !ok || len(strings.trim_space(raw)) == 0 {
		return
	}
	want_desktop := false
	want_docker := false
	want_kube := false
	copy := raw
	for item in strings.split_iterator(&copy, ",") {
		p := strings.to_lower(strings.trim_space(item), context.temp_allocator)
		switch p {
		case "", "off", "0", "false", "no":
		case "desktop":
			want_desktop = true
		case "docker":
			want_docker = true
		case "kube":
			want_kube = true
		case "full":
			want_desktop = true
			want_docker = true
			want_kube = true
		}
	}
	parts := make([dynamic]string, context.temp_allocator)
	if want_desktop {
		if path := resolve_xdg_config_home(allocator); len(path) > 0 {
			append_unique_owned(&cfg.extra_rw, path)
			append(&parts, "desktop")
		}
	}
	if want_docker {
		if sock := resolve_docker_sock(allocator); len(sock) > 0 {
			append_unique_owned(&cfg.extra_sock, sock)
			cfg.keep_docker_host = true
			append(&parts, "docker")
		}
	}
	if want_kube {
		kube_ok := secrets_allow_mentions_kube()
		if kube_ok {
			cfg.keep_kubeconfig = true
			append(&parts, "kube")
		} else {
			append(&parts, "kube-blocked")
		}
	}
	if len(parts) > 0 {
		delete(cfg.ops_label)
		cfg.ops_label = strings.join(parts[:], ",", allocator)
	}
}

resolve_xdg_config_home :: proc(allocator := context.allocator) -> string {
	if xdg, ok := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator); ok && len(xdg) > 0 {
		if filepath.is_abs(xdg) {
			return strings.clone(xdg, allocator)
		}
	}
	home, hok := os.lookup_env("HOME", context.temp_allocator)
	if !hok || len(home) == 0 {
		return ""
	}
	joined, jerr := filepath.join({home, ".config"}, allocator)
	if jerr != nil {
		return ""
	}
	return joined
}

resolve_docker_sock :: proc(allocator := context.allocator) -> string {
	candidates := []string{"/var/run/docker.sock", "/run/docker.sock"}
	for c in candidates {
		if os.exists(c) {
			return strings.clone(c, allocator)
		}
	}
	// Grant the usual path even if missing so Landlock rule is ready after daemon start.
	return strings.clone("/var/run/docker.sock", allocator)
}

secrets_allow_mentions_kube :: proc() -> bool {
	raw, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
	if !ok || len(raw) == 0 {
		return false
	}
	lower := strings.to_lower(raw, context.temp_allocator)
	return strings.contains(lower, ".kube") || strings.contains(lower, "kubeconfig")
}

/*
Parse comma-separated absolute paths into owned extras.
Relative paths are rejected (TOCTOU: caller must pass abs paths).
*/
parse_extra_paths :: proc(raw: string, out: ^[dynamic]string, allocator := context.allocator) {
	copy := raw
	for item in strings.split_iterator(&copy, ",") {
		p := strings.trim_space(item)
		if len(p) == 0 {
			continue
		}
		if !filepath.is_abs(p) {
			continue
		}
		clean, _ := filepath.clean(p, context.temp_allocator)
		append_unique_owned(out, strings.clone(clean, allocator))
	}
}

append_unique_owned :: proc(list: ^[dynamic]string, path: string) {
	if len(path) == 0 {
		return
	}
	for existing in list {
		if existing == path {
			delete(path)
			return
		}
	}
	append(list, path)
}

ops_summary_line :: proc(cfg: Config, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(cfg.ops_label) > 0 {
		fmt.sbprintf(&b, "ops=%s", cfg.ops_label)
	} else {
		strings.write_string(&b, "ops=off")
	}
	if len(cfg.extra_rw) > 0 {
		fmt.sbprintf(&b, " extra_rw=%d", len(cfg.extra_rw))
	}
	if len(cfg.extra_ro) > 0 {
		fmt.sbprintf(&b, " extra_ro=%d", len(cfg.extra_ro))
	}
	if len(cfg.extra_sock) > 0 {
		fmt.sbprintf(&b, " socks=%d", len(cfg.extra_sock))
	}
	if cfg.keep_docker_host {
		strings.write_string(&b, " docker_host=keep")
	}
	if cfg.keep_kubeconfig {
		strings.write_string(&b, " kubeconfig=keep")
	}
	return strings.to_string(b)
}
