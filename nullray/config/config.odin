// SPDX-License-Identifier: 0BSD
/*
Load and merge KEY=value pairs in ~/.config/nullray/env.
load_env_file does not overwrite keys already set in the process.
merge_env_keys upserts keys, preserves comments, and set_env for the process.
*/

package config

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

Env_KV :: struct {
	key: string,
	val: string,
}

env_path :: proc(allocator := context.allocator) -> string {
	base := sandbox.resolve_config_dir(context.temp_allocator)
	joined, err := filepath.join({base, "env"}, allocator)
	if err != nil {
		return fmt.aprintf("%s/env", base, allocator = allocator)
	}
	return joined
}

load_env_file :: proc() -> (loaded: int, err: string) {
	path := env_path(context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		if rerr == os.General_Error.Not_Exist {
			return 0, ""
		}
		return 0, fmt.aprintf("read env failed: %v", rerr)
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	for raw in lines {
		line := strings.trim_space(raw)
		if len(line) == 0 || strings.has_prefix(line, "#") {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		val := strings.trim_space(line[eq + 1:])
		if len(val) >= 2 {
			if (val[0] == '"' && val[len(val) - 1] == '"') || (val[0] == '\'' && val[len(val) - 1] == '\'') {
				val = val[1:len(val) - 1]
			}
		}
		if len(key) == 0 {
			continue
		}
		if _, exists := os.lookup_env(key, context.temp_allocator); exists {
			continue
		}
		os.set_env(key, val)
		loaded += 1
	}
	_ = constants.APP_NAME
	return loaded, ""
}

setup_done_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SETUP_DONE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

// Merge keys into an env file body. Preserves comments, blanks, and unknown keys.
merge_env_body :: proc(existing: string, kvs: []Env_KV, allocator := context.allocator) -> string {
	lines := strings.split_lines(existing, context.temp_allocator)
	out := make([dynamic]string, context.temp_allocator)
	seen := make(map[string]bool, context.temp_allocator)

	for raw in lines {
		line := raw
		trim := strings.trim_space(line)
		if len(trim) == 0 || strings.has_prefix(trim, "#") {
			append(&out, line)
			continue
		}
		eq := strings.index_byte(trim, '=')
		if eq <= 0 {
			append(&out, line)
			continue
		}
		key := strings.trim_space(trim[:eq])
		replaced := false
		for kv in kvs {
			if kv.key == key {
				append(&out, fmt.tprintf("%s=%s", kv.key, kv.val))
				seen[key] = true
				replaced = true
				break
			}
		}
		if !replaced {
			append(&out, line)
		}
	}
	for kv in kvs {
		if seen[kv.key] {
			continue
		}
		append(&out, fmt.tprintf("%s=%s", kv.key, kv.val))
		seen[kv.key] = true
	}
	return strings.join(out[:], "\n", allocator)
}

merge_env_keys :: proc(kvs: []Env_KV, path := "", apply_process := true) -> (err: string) {
	p := path
	owned_path: string
	if len(p) == 0 {
		owned_path = env_path()
		p = owned_path
	}
	defer if len(owned_path) > 0 {
		delete(owned_path)
	}

	dir := filepath.dir(p)
	_ = os.make_directory_all(dir)

	existing := ""
	if data, rerr := os.read_entire_file(p, context.temp_allocator); rerr == nil {
		existing = string(data)
	} else if rerr != os.General_Error.Not_Exist {
		return fmt.aprintf("read env failed: %v", rerr)
	}

	body := merge_env_body(existing, kvs, context.temp_allocator)
	if !strings.has_suffix(body, "\n") {
		body = fmt.tprintf("%s\n", body)
	}
	f, oerr := os.open(p, {.Write, .Create, .Trunc}, {.Read_User, .Write_User})
	if oerr != nil {
		return fmt.aprintf("write env failed: %v", oerr)
	}
	_, werr := os.write(f, transmute([]byte)body)
	os.close(f)
	if werr != nil {
		return fmt.aprintf("write env failed: %v", werr)
	}
	if apply_process {
		for kv in kvs {
			os.set_env(kv.key, kv.val)
		}
	}
	return ""
}
