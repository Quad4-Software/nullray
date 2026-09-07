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
	"LANG",
	"LC_",
	"XDG_",
	"HOME",
	"USER",
	"PATH",
	"SSL_CERT_",
	"CURL_",
	"OLLAMA_",
	"OPENROUTER_",
	"OPENCODE_",
	"LM_API_",
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

env_scrub :: proc() {
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
		if env_keep(key) {
			append(&keys, strings.clone(key, context.temp_allocator))
		}
	}
	for e in entries {
		eq := strings.index_byte(e, '=')
		if eq <= 0 {
			continue
		}
		key := e[:eq]
		if !env_keep(key) {
			os.unset_env(key)
		}
	}
	_ = keys
	_ = constants.APP_NAME
}

@(private)
env_keep :: proc(key: string) -> bool {
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
