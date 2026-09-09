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
	"/nullray/sessions/",
	"/nullray/crashes/",
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

value_looks_secret :: proc(value: string) -> bool {
	trimmed := strings.trim_space(value)
	lower := strings.to_lower(trimmed, context.temp_allocator)
	for marker in SECRET_VALUE_MARKERS {
		if strings.contains(lower, marker) {
			return true
		}
	}
	parts := [4][2]string{
		{"gh", "p_"},
		{"github_", "pat_"},
		{"xo", "xb-"},
		{"xo", "xp-"},
	}
	for p in parts {
		prefix := strings.concatenate({p[0], p[1]}, context.temp_allocator)
		if strings.has_prefix(lower, prefix) {
			return true
		}
	}
	if strings.has_prefix(lower, "sk-") {
		return true
	}
	pem := strings.concatenate({"-----begin ", "private key-----"}, context.temp_allocator)
	return strings.contains(lower, pem)
}

/*
True when path looks secret and is not on NULLRAY_SECRETS_ALLOW.
Follows a short symlink chain so `ln -s .env leak` stays blocked.
*/
path_is_secret_blocked :: proc(abs_path: string) -> bool {
	if len(abs_path) == 0 {
		return false
	}
	seen := abs_path
	for _ in 0 ..< 8 {
		if path_is_secret_blocked_once(seen) {
			return true
		}
		target, err := os.read_link(seen, context.temp_allocator)
		if err != nil || len(target) == 0 {
			return false
		}
		if filepath.is_abs(target) {
			seen = target
		} else {
			joined, jerr := filepath.join({filepath.dir(seen), target}, context.temp_allocator)
			if jerr != nil {
				return false
			}
			seen, _ = filepath.clean(joined, context.temp_allocator)
		}
	}
	return path_is_secret_blocked_once(seen)
}

@(private)
path_is_secret_blocked_once :: proc(abs_path: string) -> bool {
	clean, _ := filepath.clean(abs_path, context.temp_allocator)
	lower := strings.to_lower(clean, context.temp_allocator)
	base := filepath.base(clean)
	base_l := strings.to_lower(base, context.temp_allocator)

	if secrets_explicitly_allowed(clean) {
		return false
	}

	// Credential file under ~/.config/nullray/env (basename alone is too broad).
	if base_l == "env" {
		parent := filepath.base(filepath.dir(clean))
		if strings.to_lower(parent, context.temp_allocator) == "nullray" {
			return true
		}
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
		// Allow the path or paths under an allowed directory. Do not unlock
		// parents when a child file is listed (that widened .ssh accidentally).
		if clean == allow || path_beneath(clean, allow) {
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
Strips quotes so `cat .e''nv` still matches.
*/
shell_mentions_secret :: proc(cmd: string) -> (blocked: bool, hint: string) {
	scan := shell_cmd_strip_quotes(cmd, context.temp_allocator)
	lower := strings.to_lower(scan, context.temp_allocator)
	tokens := strings.fields(scan, context.temp_allocator)
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
shell_cmd_strip_quotes :: proc(cmd: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for i in 0 ..< len(cmd) {
		c := cmd[i]
		if c == '\'' || c == '"' {
			continue
		}
		strings.write_byte(&b, c)
	}
	return strings.to_string(b)
}

@(private)
secrets_allow_token :: proc(token: string) -> bool {
	raw, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
	if !ok {
		return false
	}
	return strings.contains(raw, token)
}
