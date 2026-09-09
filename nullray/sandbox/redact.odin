// SPDX-License-Identifier: 0BSD
/*
Outbound privacy redaction for home paths, usernames, and secret-shaped tokens.

Env scrub (env.odin) strips cloud and SSH secrets from the process environment.
Redaction here rewrites paths, usernames, and credential values in text sent to models or logs.
*/

package sandbox

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"
import "nullray:constants"

REDACTED_SECRET :: "[redacted]"

privacy_redact_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRIVACY_REDACT, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		case "1", "true", "on", "yes":
			return true
		}
	}
	if v, ok := os.lookup_env(constants.ENV_PRIVACY, context.temp_allocator); ok {
		return !(v == "0" || v == "false" || v == "off")
	}
	return true
}

redact_secrets :: proc(text: string, allocator := context.allocator) -> string {
	if len(text) == 0 || !privacy_redact_enabled() {
		return strings.clone(text, allocator)
	}

	out := strings.clone(text, allocator)
	home := ""
	if h, ok := os.lookup_env("HOME", context.temp_allocator); ok {
		home = h
	}
	user := ""
	if u, ok := os.lookup_env("USER", context.temp_allocator); ok {
		user = u
	}
	if len(home) == 0 {
		if st := state(); st != nil && len(st.config_dir) > 0 {
			parent := filepath.dir(st.config_dir)
			home = filepath.dir(parent)
		}
	}

	if len(home) > 0 && strings.contains(out, home) {
		rep, _ := strings.replace_all(out, home, "~", allocator)
		delete(out, allocator)
		out = rep
	}

	if len(user) > 1 {
		slash_user := fmt.tprintf("/home/%s", user)
		if strings.contains(out, slash_user) {
			rep, _ := strings.replace_all(out, slash_user, "/home/<user>", allocator)
			delete(out, allocator)
			out = rep
		}
		rep2 := redact_username_token(out, user, allocator)
		delete(out, allocator)
		out = rep2
	}

	tok := redact_secret_tokens(out, allocator)
	delete(out, allocator)
	return tok
}

/*
Replace secret-shaped tokens and assignment values in outbound text.
*/
redact_secret_tokens :: proc(text: string, allocator := context.allocator) -> string {
	if len(text) == 0 {
		return strings.clone(text, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(text) {
		// Marker assignments: api_key=..., Authorization: Bearer ...
		matched := false
		lower_rest := strings.to_lower(text[i:], context.temp_allocator)
		for marker in SECRET_VALUE_MARKERS {
			if strings.has_prefix(lower_rest, marker) {
				strings.write_string(&b, text[i:i + len(marker)])
				i += len(marker)
				for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '"' || text[i] == '\'') {
					strings.write_byte(&b, text[i])
					i += 1
				}
				strings.write_string(&b, REDACTED_SECRET)
				for i < len(text) && !is_secret_value_end(text[i]) {
					i += 1
				}
				matched = true
				break
			}
		}
		if matched {
			continue
		}
		// Standalone token prefixes: sk-, ghp_, github_pat_, xoxb-, xoxp-
		if secret_token_at(text, i) {
			strings.write_string(&b, REDACTED_SECRET)
			i = secret_token_end(text, i)
			continue
		}
		// Proxy URLs with userinfo
		if proxy_userinfo_at(text, i) {
			scheme_end := strings.index(text[i:], "://")
			at := strings.index_byte(text[i + scheme_end + 3:], '@')
			strings.write_string(&b, text[i:i + scheme_end + 3])
			strings.write_string(&b, REDACTED_SECRET)
			strings.write_byte(&b, '@')
			i = i + scheme_end + 3 + at + 1
			continue
		}
		strings.write_byte(&b, text[i])
		i += 1
	}
	return strings.to_string(b)
}

@(private)
is_secret_value_end :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '"' || c == '\'' || c == ',' || c == ';' || c == '&'
}

@(private)
secret_token_at :: proc(text: string, i: int) -> bool {
	rest := text[i:]
	lower := strings.to_lower(rest, context.temp_allocator)
	prefixes := []string{"sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-", "gho_", "ghu_", "ghs_"}
	for p in prefixes {
		if strings.has_prefix(lower, p) {
			if i > 0 {
				prev := text[i - 1]
				if unicode.is_alpha(rune(prev)) || unicode.is_digit(rune(prev)) || prev == '_' {
					return false
				}
			}
			return true
		}
	}
	return false
}

@(private)
secret_token_end :: proc(text: string, start: int) -> int {
	i := start
	for i < len(text) {
		c := text[i]
		if unicode.is_alpha(rune(c)) || unicode.is_digit(rune(c)) || c == '-' || c == '_' || c == '.' {
			i += 1
			continue
		}
		break
	}
	return i
}

@(private)
proxy_userinfo_at :: proc(text: string, i: int) -> bool {
	rest := text[i:]
	lower := strings.to_lower(rest, context.temp_allocator)
	if !(strings.has_prefix(lower, "http://") || strings.has_prefix(lower, "https://")) {
		return false
	}
	scheme_end := strings.index(rest, "://")
	if scheme_end < 0 {
		return false
	}
	hostpart := rest[scheme_end + 3:]
	at := strings.index_byte(hostpart, '@')
	if at <= 0 {
		return false
	}
	slash := strings.index_byte(hostpart, '/')
	if slash >= 0 && slash < at {
		return false
	}
	return strings.contains(hostpart[:at], ":")
}

@(private)
redact_username_token :: proc(text, user: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	ulen := len(user)
	for i < len(text) {
		if i + ulen <= len(text) && text[i:i + ulen] == user {
			prev_ok := i == 0 || text[i - 1] == '/' || text[i - 1] == '\\' || text[i - 1] == ' '
			next_ok :=
				i + ulen >= len(text) ||
				text[i + ulen] == '/' ||
				text[i + ulen] == '\\' ||
				text[i + ulen] == ' ' ||
				text[i + ulen] == '\n' ||
				text[i + ulen] == '\r'
			if prev_ok && next_ok {
				strings.write_string(&b, "<user>")
				i += ulen
				continue
			}
		}
		strings.write_byte(&b, text[i])
		i += 1
	}
	return strings.to_string(b)
}
