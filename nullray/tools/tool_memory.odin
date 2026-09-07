// SPDX-License-Identifier: 0BSD
/*
Project memory tools.
*/

package tools

import "core:strings"
import project_memory "nullray:memory"

tool_memory_get :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Get(key, allocator)
}

tool_memory_put :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	value, value_err := json_arg_string(args_json, "value", allocator)
	if value_err != "" {
		return "", value_err
	}
	defer delete(value)
	return project_memory.Put(key, value, allocator)
}

tool_memory_list :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	filter, err := json_arg_string_optional(args_json, "filter", "", allocator)
	if err != "" {
		return "", err
	}
	defer delete(filter)
	result := project_memory.List(strings.trim_space(filter), allocator)
	return result, ""
}
