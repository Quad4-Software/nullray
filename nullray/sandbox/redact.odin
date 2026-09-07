/*
Outbound privacy redaction for home paths and username.

Env scrub (env.odin) strips cloud and SSH secrets from the process environment.
Redaction here rewrites paths and usernames in text sent to models or logs.
*/

package sandbox

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

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
		delete(out)
		out = rep
	}

	if len(user) > 1 {
		slash_user := fmt.tprintf("/home/%s", user)
		if strings.contains(out, slash_user) {
			rep, _ := strings.replace_all(out, slash_user, "/home/<user>", allocator)
			delete(out)
			out = rep
		}
		rep2 := redact_username_token(out, user, allocator)
		delete(out)
		out = rep2
	}

	return out
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
