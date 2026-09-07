// SPDX-License-Identifier: 0BSD
/*
Optional local audit JSONL when NULLRAY_AUDIT_LOG=1. No phone-home.
*/

package store

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

audit_log_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_AUDIT_LOG, context.temp_allocator); ok {
		lv := strings.to_lower(v, context.temp_allocator)
		return lv == "1" || lv == "true" || lv == "yes" || lv == "on"
	}
	return false
}

audit_log_path :: proc(allocator := context.allocator) -> string {
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	return fmt.aprintf("%s/audit.jsonl", cfg, allocator = allocator)
}

/*
Append one audit line. path_hash is an opaque token (not file contents).
*/
audit_log_append :: proc(event, tool_name, path_hash, finding_id: string) {
	if !audit_log_enabled() {
		return
	}
	path := audit_log_path(context.temp_allocator)
	dir := sandbox.resolve_config_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	ts := time.now()
	line := fmt.aprintf(
		"{\"ts\":%d,\"event\":\"%s\",\"tool\":\"%s\",\"path_hash\":\"%s\",\"finding\":\"%s\"}\n",
		ts._nsec,
		sanitize_json_token(event),
		sanitize_json_token(tool_name),
		sanitize_json_token(path_hash),
		sanitize_json_token(finding_id),
		allocator = context.temp_allocator,
	)
	f, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if err != nil {
		return
	}
	defer os.close(f)
	_, _ = os.write(f, transmute([]u8)line)
}

@(private)
sanitize_json_token :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for c in s {
		switch c {
		case '"', '\\':
			strings.write_byte(&b, '_')
		case '\n', '\r', '\t':
			strings.write_byte(&b, ' ')
		case:
			if c < 32 {
				strings.write_byte(&b, ' ')
			} else {
				strings.write_rune(&b, c)
			}
		}
	}
	return strings.to_string(b)
}
