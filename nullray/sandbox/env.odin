// SPDX-License-Identifier: 0BSD
/*
Privacy: rebuild environ to an allowlist before agent work.
*/

package sandbox

import "core:os"
import "core:strings"
import "nullray:constants"

ALLOWED_ENV_PREFIXES :: []string{
	"NULLRAY_",
	"TERM",
	"COLORTERM",
	"COLUMNS",
	"LINES",
	"NO_COLOR",
	"FORCE_COLOR",
	"WSL_",
	"WT_",
	"LANG",
	"LC_",
	"XDG_",
	"HOME",
	"USER",
	"PATH",
	"SSL_CERT_",
	"OLLAMA_",
	"OPENROUTER_",
	"OPENCODE_",
	"LM_API_",
	"HTTP_PROXY",
	"HTTPS_PROXY",
	"ALL_PROXY",
	"NO_PROXY",
	"http_proxy",
	"https_proxy",
	"all_proxy",
	"no_proxy",
}

DENIED_ENV_PREFIXES :: []string{
	"LD_",
	"SSH_",
	"AWS_",
	"GCP_",
	"GOOGLE_",
	"AZURE_",
	"DOCKER_",
	"KUBE",
	"NPM_",
	"NODE_",
}

env_scrub :: proc(cfg: Config = {}) {
	entries, err := os.environ(context.temp_allocator)
	if err != nil {
		return
	}
	keys := make([dynamic]string, context.temp_allocator)
	for e in entries {
		eq := strings.index_byte(e, '=')
		if eq <= 0 {
			continue
		}
		key := e[:eq]
		if env_keep(key, cfg) {
			append(&keys, strings.clone(key, context.temp_allocator))
		}
	}
	for e in entries {
		eq := strings.index_byte(e, '=')
		if eq <= 0 {
			continue
		}
		key := e[:eq]
		if !env_keep(key, cfg) {
			os.unset_env(key)
		}
	}
	_ = keys
	_ = constants.APP_NAME
}

@(private)
env_keep :: proc(key: string, cfg: Config = {}) -> bool {
	if cfg.keep_docker_host && key == "DOCKER_HOST" {
		return true
	}
	if cfg.keep_kubeconfig && (key == "KUBECONFIG" || key == "KUBE_CONFIG") {
		return true
	}
	for d in DENIED_ENV_PREFIXES {
		if strings.has_prefix(key, d) {
			return false
		}
	}
	for a in ALLOWED_ENV_PREFIXES {
		if key == a || strings.has_prefix(key, a) {
			return true
		}
	}
	return false
}
