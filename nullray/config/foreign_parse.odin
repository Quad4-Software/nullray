// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Small readers for foreign tool config files: capped file reads, JSON with a
JSONC fallback, env references ($VAR, {env:VAR}, {file:}), dotenv pairs, and
just enough TOML and YAML to lift the handful of scalars each tool stores.
Nothing here executes helper commands.
*/

package config

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"

FOREIGN_MAX_BYTES :: 512 * 1024

foreign_home :: proc() -> string {
	when ODIN_OS == .Windows {
		if v, ok := os.lookup_env("USERPROFILE", context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	}
	if v, ok := os.lookup_env("HOME", context.temp_allocator); ok && len(v) > 0 {
		return v
	}
	return ""
}

foreign_xdg_config :: proc() -> string {
	when ODIN_OS == .Windows {
		if v, ok := os.lookup_env("APPDATA", context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	} else {
		if v, ok := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	}
	home := foreign_home()
	if len(home) == 0 {
		return ""
	}
	return foreign_join(home, ".config")
}

foreign_xdg_data :: proc() -> string {
	when ODIN_OS == .Windows {
		if v, ok := os.lookup_env("LOCALAPPDATA", context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	} else {
		if v, ok := os.lookup_env("XDG_DATA_HOME", context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	}
	home := foreign_home()
	if len(home) == 0 {
		return ""
	}
	return foreign_join(home, ".local", "share")
}

foreign_join :: proc(parts: ..string) -> string {
	p, err := filepath.join(parts, context.temp_allocator)
	if err != nil {
		return strings.concatenate(parts, context.temp_allocator)
	}
	return p
}

// Display form of a path for notes and doctor: home collapses to ~.
foreign_disp :: proc(path: string) -> string {
	home := foreign_home()
	if len(home) > 0 && strings.has_prefix(path, home) {
		return fmt_tilde(path, home)
	}
	return path
}

@(private)
fmt_tilde :: proc(path, home: string) -> string {
	if len(path) == len(home) {
		return "~"
	}
	if path[len(home)] == '/' || path[len(home)] == '\\' {
		return strings.concatenate({"~", path[len(home):]}, context.temp_allocator)
	}
	return path
}

// Read a config file with a size cap. Returns body plus mtime in nsec.
foreign_read :: proc(path: string) -> (body: string, mtime: i64, ok: bool) {
	fi, serr := os.stat(path, context.temp_allocator)
	if serr != nil || fi.size > FOREIGN_MAX_BYTES {
		return "", 0, false
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return "", 0, false
	}
	return string(data), fi.modification_time._nsec, true
}

@(private)
jsonc_strip :: proc(body: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	in_str := false
	esc := false
	i := 0
	for i < len(body) {
		c := body[i]
		if in_str {
			strings.write_byte(&b, c)
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				in_str = false
			}
			i += 1
			continue
		}
		if c == '"' {
			in_str = true
			strings.write_byte(&b, c)
			i += 1
			continue
		}
		if c == '/' && i + 1 < len(body) && body[i + 1] == '/' {
			for i < len(body) && body[i] != '\n' {
				i += 1
			}
			continue
		}
		if c == '/' && i + 1 < len(body) && body[i + 1] == '*' {
			i += 2
			for i + 1 < len(body) && !(body[i] == '*' && body[i + 1] == '/') {
				i += 1
			}
			i += 2
			continue
		}
		strings.write_byte(&b, c)
		i += 1
	}
	// Trailing commas are legal JSONC, so drop a comma whose next non-space
	// byte closes an object or array.
	src := strings.to_string(b)
	out: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	for i in 0 ..< len(src) {
		c := src[i]
		if c == ',' {
			j := i + 1
			for j < len(src) && (src[j] == ' ' || src[j] == '\t' || src[j] == '\n' || src[j] == '\r') {
				j += 1
			}
			if j < len(src) && (src[j] == '}' || src[j] == ']') {
				continue
			}
		}
		strings.write_byte(&out, c)
	}
	return strings.to_string(out)
}

// Parse a JSON (or JSONC) config file. Tree lives on temp_allocator.
foreign_json :: proc(path: string) -> (doc: json.Value, mtime: i64, ok: bool) {
	body, mt, rok := foreign_read(path)
	if !rok {
		return nil, 0, false
	}
	v, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		v, perr = json.parse_string(jsonc_strip(body), .JSON, allocator = context.temp_allocator)
		if perr != .None {
			return nil, 0, false
		}
	}
	return v, mt, true
}

fj_obj :: proc(v: json.Value) -> (json.Object, bool) {
	obj, ok := v.(json.Object)
	return obj, ok
}

fj_str :: proc(v: json.Value) -> string {
	s, ok := v.(json.String)
	if !ok {
		return ""
	}
	return string(s)
}

fj_get :: proc(v: json.Value, key: string) -> json.Value {
	obj, ok := fj_obj(v)
	if !ok {
		return nil
	}
	return obj[key]
}

fj_dig :: proc(v: json.Value, keys: ..string) -> json.Value {
	cur := v
	for k in keys {
		cur = fj_get(cur, k)
		if cur == nil {
			return nil
		}
	}
	return cur
}

// Resolve env references and command/file indirections. Returns "" for
// anything we refuse to touch (shell commands) or cannot resolve.
foreign_resolve_value :: proc(v: string) -> string {
	s := strings.trim_space(v)
	if len(s) == 0 || strings.has_prefix(s, "!") {
		return ""
	}
	if strings.has_prefix(s, "{env:") && strings.has_suffix(s, "}") {
		name := s[5:len(s) - 1]
		if env, ok := os.lookup_env(name, context.temp_allocator); ok {
			return strings.trim_space(env)
		}
		return ""
	}
	if strings.has_prefix(s, "{file:") && strings.has_suffix(s, "}") {
		p := strings.trim_space(s[6:len(s) - 1])
		if strings.has_prefix(p, "~/") {
			home := foreign_home()
			if len(home) == 0 {
				return ""
			}
			p = foreign_join(home, p[2:])
		}
		body, _, ok := foreign_read(p)
		if !ok {
			return ""
		}
		return strings.trim_space(body)
	}
	if strings.has_prefix(s, "${") && strings.has_suffix(s, "}") {
		inner := s[2:len(s) - 1]
		if idx := strings.index(inner, ":-"); idx > 0 {
			if env, ok := os.lookup_env(inner[:idx], context.temp_allocator); ok && len(env) > 0 {
				return env
			}
			return inner[idx + 2:]
		}
		if env, ok := os.lookup_env(inner, context.temp_allocator); ok {
			return env
		}
		return ""
	}
	if strings.has_prefix(s, "$") && len(s) > 1 {
		if env, ok := os.lookup_env(s[1:], context.temp_allocator); ok {
			return env
		}
		return ""
	}
	return s
}

foreign_key_ok :: proc(v: string) -> bool {
	if len(v) < 8 {
		return false
	}
	for r in v {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			return false
		}
	}
	return true
}

// KEY=VALUE lines from a dotenv file, quotes and export prefix stripped.
foreign_dotenv_pairs :: proc(body: string, pairs: ^[dynamic]Env_KV) {
	for raw in strings.split_lines(body, context.temp_allocator) {
		line := strings.trim_space(raw)
		if len(line) == 0 || strings.has_prefix(line, "#") {
			continue
		}
		line = strings.trim_prefix(line, "export ")
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		val := strings.trim_space(line[eq + 1:])
		val = unquote(val)
		if len(key) > 0 && len(val) > 0 {
			append(pairs, Env_KV{key = key, val = val})
		}
	}
}
