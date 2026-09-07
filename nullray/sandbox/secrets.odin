// SPDX-License-Identifier: 0BSD
/*
Blocked secret paths for tools and shell unless explicitly allowed.
*/

package sandbox

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

SECRET_BASENAMES :: []string{
	".env",
	".env.local",
	".env.production",
	".env.development",
	".env.staging",
	".env.test",
	"credentials",
	"credentials.json",
	"secrets.json",
	"secret.json",
	"secrets.yaml",
	"secrets.yml",
	".npmrc",
	".pypirc",
	".netrc",
	".pgpass",
	"id_rsa",
	"id_dsa",
	"id_ecdsa",
	"id_ed25519",
	"private.key",
	"service-account.json",
	"google-services.json",
}

SECRET_SUFFIXES :: []string{
	".pem",
	".p12",
	".pfx",
	".key",
	".keystore",
	".jks",
}

SECRET_PATH_PARTS :: []string{
	"/.ssh/",
	"/.aws/",
	"/.gnupg/",
	"/.kube/",
	"/secrets/",
	"/.secrets/",
}

SECRET_VALUE_MARKERS :: []string{
	"api_key=",
	"api-key=",
	"apikey=",
	"secret=",
	"password=",
	"passwd=",
	"private_key=",
	"access_token=",
	"refresh_token=",
	"authorization: bearer ",
}

SECRET_VALUE_PREFIXES :: []string{"sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-"}

value_looks_secret :: proc(value: string) -> bool {
	trimmed := strings.trim_space(value)
	lower := strings.to_lower(trimmed, context.temp_allocator)
	for marker in SECRET_VALUE_MARKERS {
		if strings.contains(lower, marker) {
			return true
		}
	}
	for prefix in SECRET_VALUE_PREFIXES {
		if strings.has_prefix(lower, prefix) {
			return true
		}
	}
	return strings.contains(lower, "-----begin private key-----")
}

/*
True when path looks secret and is not on NULLRAY_SECRETS_ALLOW.
*/
path_is_secret_blocked :: proc(abs_path: string) -> bool {
	if len(abs_path) == 0 {
		return false
	}
	clean, _ := filepath.clean(abs_path, context.temp_allocator)
	lower := strings.to_lower(clean, context.temp_allocator)
	base := filepath.base(clean)
	base_l := strings.to_lower(base, context.temp_allocator)

	if secrets_explicitly_allowed(clean) {
		return false
	}

	for name in SECRET_BASENAMES {
		if base_l == name {
			return true
		}
	}
	// .env.* variants
	if strings.has_prefix(base_l, ".env.") || base_l == ".env" {
		return true
	}
	for suf in SECRET_SUFFIXES {
		if strings.has_suffix(base_l, suf) {
			return true
		}
	}
	for part in SECRET_PATH_PARTS {
		if strings.contains(lower, part) {
			return true
		}
	}
	return false
}

secrets_explicitly_allowed :: proc(abs_path: string) -> bool {
	raw, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
	if !ok || len(raw) == 0 {
		return false
	}
	clean, _ := filepath.clean(abs_path, context.temp_allocator)
	copy := raw
	for item in strings.split_iterator(&copy, ",") {
		p := strings.trim_space(item)
		if len(p) == 0 {
			continue
		}
		allow, _ := filepath.clean(p, context.temp_allocator)
		if !filepath.is_abs(allow) {
			if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
				joined, jerr := filepath.join({cwd, allow}, context.temp_allocator)
				if jerr == nil {
					allow = joined
				}
			}
		}
		if clean == allow || path_beneath(clean, allow) || path_beneath(allow, clean) {
			return true
		}
		// Basename allow e.g. ".env"
		if filepath.base(clean) == filepath.base(allow) && strings.contains(p, filepath.base(allow)) {
			if allow == filepath.base(allow) || strings.has_prefix(p, "*") {
				return true
			}
		}
	}
	return false
}

/*
Detect secret file references inside a shell command (cat .env bypass etc).
*/
shell_mentions_secret :: proc(cmd: string) -> (blocked: bool, hint: string) {
	lower := strings.to_lower(cmd, context.temp_allocator)
	tokens := strings.fields(cmd, context.temp_allocator)
	for tok in tokens {
		t := strings.trim(tok, `"'`)
		if len(t) == 0 {
			continue
		}
		// Resolve relative against workspace if possible
		cand := t
		if !filepath.is_abs(cand) {
			if st := state(); st != nil && len(st.workspace) > 0 {
				joined, jerr := filepath.join({st.workspace, cand}, context.temp_allocator)
				if jerr == nil {
					cand = joined
				}
			}
		}
		if path_is_secret_blocked(cand) || path_is_secret_blocked(t) {
			return true, filepath.base(t)
		}
		base := filepath.base(t)
		base_l := strings.to_lower(base, context.temp_allocator)
		if base_l == ".env" || strings.has_prefix(base_l, ".env.") {
			if !secrets_explicitly_allowed(t) {
				return true, base
			}
		}
	}
	for name in SECRET_BASENAMES {
		if strings.contains(lower, name) {
			if !secrets_allow_token(name) {
				return true, name
			}
		}
	}
	if strings.contains(lower, ".env") && !secrets_allow_token(".env") {
		return true, ".env"
	}
	return false, ""
}

@(private)
secrets_allow_token :: proc(token: string) -> bool {
	raw, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
	if !ok {
		return false
	}
	return strings.contains(raw, token)
}
