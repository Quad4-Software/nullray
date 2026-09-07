/*
Shell and write permission levels: ask, allow, yolo.
*/

package tools

import "core:os"
import "core:strings"
import "nullray:constants"

Perms :: enum {
	Ask,
	Allow,
	Yolo,
}

perms_from_string :: proc(s: string) -> (Perms, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "ask", "confirm", "prompt":
		return .Ask, true
	case "allow", "default", "list":
		return .Allow, true
	case "yolo", "auto", "autonomy", "full":
		return .Yolo, true
	}
	return .Allow, false
}

perms_string :: proc(p: Perms) -> string {
	switch p {
	case .Ask:
		return "ask"
	case .Allow:
		return "allow"
	case .Yolo:
		return "yolo"
	}
	return "allow"
}

perms_from_env :: proc() -> Perms {
	if v, ok := os.lookup_env(constants.ENV_PERMS, context.temp_allocator); ok {
		if p, found := perms_from_string(v); found {
			return p
		}
	}
	if v, aok := os.lookup_env(constants.ENV_AUTONOMY, context.temp_allocator); aok && v == "1" {
		return .Yolo
	}
	if v, aok := os.lookup_env(constants.ENV_SHELL_AUTONOMY, context.temp_allocator); aok && v == "1" {
		return .Yolo
	}
	if v, cok := os.lookup_env(constants.ENV_SHELL_CONFIRM, context.temp_allocator); cok && v == "1" {
		return .Ask
	}
	return .Allow
}
