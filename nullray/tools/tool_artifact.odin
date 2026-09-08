// SPDX-License-Identifier: 0BSD
/*
read_artifact and grep_artifact tools for LID peek into offloaded tool payloads.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:store"

tool_read_artifact :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, ierr := json_arg_string(args_json, "id", allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	defer delete(id)
	offset_s, _ := json_arg_string_optional(args_json, "offset", "0", context.temp_allocator)
	limit_s, _ := json_arg_string_optional(args_json, "limit", "", context.temp_allocator)
	body, rerr := store.artifact_read(id, allocator)
	if len(rerr) > 0 {
		return "", rerr
	}
	offset := 0
	limit := artifact_read_lines_default()
	if n, ok := parse_positive_int(offset_s); ok {
		offset = n
	}
	if len(strings.trim_space(limit_s)) > 0 {
		if n, ok := parse_positive_int(limit_s); ok {
			limit = n
		}
	}
	lines := strings.split_lines(body, context.temp_allocator)
	delete(body)
	start := 0
	if offset > 0 {
		start = offset - 1
		if start < 0 {
			start = 0
		}
		if start > len(lines) {
			start = len(lines)
		}
	}
	end := len(lines)
	if limit > 0 && start + limit < end {
		end = start + limit
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "artifact=%s lines=%d..%d of %d\n", id, start + 1, end, len(lines))
	byte_cap := constants.ARTIFACT_READ_BYTES_MAX
	used := 0
	for i in start ..< end {
		line := lines[i]
		need := len(line) + 1
		if used + need > byte_cap {
			strings.write_string(&b, "... truncated (byte cap)\n")
			break
		}
		strings.write_string(&b, line)
		used += len(line)
		if i + 1 < end {
			strings.write_byte(&b, '\n')
			used += 1
		}
	}
	return strings.to_string(b), ""
}

tool_grep_artifact :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, ierr := json_arg_string(args_json, "id", allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	defer delete(id)
	pattern, perr := json_arg_string(args_json, "pattern", allocator)
	if len(perr) > 0 {
		return "", perr
	}
	defer delete(pattern)
	return store.artifact_grep(id, pattern, allocator)
}

@(private)
artifact_read_lines_default :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_ARTIFACT_READ_LINES, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(strings.trim_space(v))
		if n_ok && n > 0 {
			return n
		}
	}
	return constants.ARTIFACT_READ_LINES_DEFAULT
}

@(private)
parse_positive_int :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 {
		return 0, false
	}
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}
