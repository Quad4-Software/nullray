// SPDX-License-Identifier: 0BSD
/*
Project memory tools.
*/

package tools

import "core:strconv"
import "core:strings"
import "nullray:constants"
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

tool_memory_delete :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Delete(key, allocator)
}

tool_memory_forget :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Forget(key, allocator)
}

tool_memory_search :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	query, err := json_arg_string(args_json, "query", allocator)
	if err != "" {
		return "", err
	}
	defer delete(query)
	limit_str, limit_err := json_arg_string_optional(args_json, "limit", "", allocator)
	if limit_err != "" {
		return "", limit_err
	}
	defer delete(limit_str)
	limit := constants.MEMORY_SEARCH_DEFAULT_LIMIT
	if len(strings.trim_space(limit_str)) > 0 {
		if n, ok := strconv.parse_int(limit_str); ok {
			limit = n
		}
	}
	result := project_memory.Search(strings.trim_space(query), limit, allocator)
	return result, ""
}
