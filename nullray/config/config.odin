/*
Load KEY=value pairs from ~/.config/nullray/env into the process environment.
Does not overwrite keys already set.
*/

package config

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

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
