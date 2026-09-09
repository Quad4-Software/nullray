// SPDX-License-Identifier: 0BSD
/*
Tests for locate CITES parsing and formatting.
*/

package subagent

import "core:strings"
import "core:testing"

@(test)
test_parse_cite_range_and_single :: proc(t: ^testing.T) {
	text := "CITES: 2\nnullray/agent/agent.odin:10-40\nnullray/tools/run.odin:5\n"
	items, none := parse_cites_list(text, 12, context.allocator)
	defer cites_destroy(items)
	testing.expect(t, !none)
	testing.expect(t, len(items) == 2)
	testing.expect(t, items[0].path == "nullray/agent/agent.odin")
	testing.expect(t, items[0].start == 10 && items[0].end == 40)
	testing.expect(t, items[1].path == "nullray/tools/run.odin")
	testing.expect(t, items[1].start == 5 && items[1].end == 5)
}

@(test)
test_parse_cites_none_trailer :: proc(t: ^testing.T) {
	items, none := parse_cites_list("searched\nCITES: none\n", 12, context.allocator)
	defer cites_destroy(items)
	testing.expect(t, none)
	testing.expect(t, len(items) == 0)
	sum := format_locate_summary("nothing found\nCITES: none\n", context.allocator)
	defer delete(sum)
	testing.expect(t, strings.has_prefix(sum, "CITES: none"))
}

@(test)
test_parse_cite_rejects_dotdot_and_abs :: proc(t: ^testing.T) {
	path, _, _, _, ok := parse_cite_line("../secret.odin:1-2")
	testing.expect(t, !ok)
	_ = path
	_, _, _, _, ok2 := parse_cite_line("/etc/passwd:1")
	testing.expect(t, !ok2)
	_, _, _, _, ok3 := parse_cite_line(`C:\Windows\system.ini:1-2`)
	testing.expect(t, !ok3)
}

@(test)
test_parse_cite_windows_drive_not_confused :: proc(t: ^testing.T) {
	// Relative path that merely contains a colon-digit range at the end.
	path, start, end, _, ok := parse_cite_line("pkg/file.odin:12-18")
	testing.expect(t, ok)
	testing.expect(t, path == "pkg/file.odin")
	testing.expect(t, start == 12 && end == 18)
}

@(test)
test_parse_cites_cap_and_sort :: proc(t: ^testing.T) {
	text := "z.odin:9\na.odin:2\na.odin:1\nb.odin:3\n"
	items, _ := parse_cites_list(text, 2, context.allocator)
	defer cites_destroy(items)
	testing.expect(t, len(items) == 2)
	testing.expect(t, items[0].path == "a.odin" && items[0].start == 1)
	testing.expect(t, items[1].path == "a.odin" && items[1].start == 2)
}

@(test)
test_format_locate_summary_soft_fail :: proc(t: ^testing.T) {
	sum := format_locate_summary("I looked around but found nothing useful.", context.allocator)
	defer delete(sum)
	testing.expect(t, strings.has_prefix(sum, "CITES: 0"))
	testing.expect(t, strings.contains(sum, "parse_note:"))
}

@(test)
test_format_locate_summary_temp_allocator :: proc(t: ^testing.T) {
	// Regression: destroy must free with the same allocator used to parse.
	raw := "CITES: 1\nlib/config_parse.py:1-12\n"
	sum := format_locate_summary(raw, context.temp_allocator)
	testing.expect(t, strings.has_prefix(sum, "CITES: 1"))
	testing.expect(t, strings.contains(sum, "lib/config_parse.py:1-12"))
	free_all(context.temp_allocator)
}

@(test)
test_locate_env_clamps :: proc(t: ^testing.T) {
	testing.expect(t, locate_steps_from_env() >= 1 && locate_steps_from_env() <= 8)
	testing.expect(t, locate_parallel_from_env() >= 1 && locate_parallel_from_env() <= 8)
	testing.expect(t, locate_max_cites_from_env() >= 1 && locate_max_cites_from_env() <= 32)
}

@(test)
test_is_locate_type :: proc(t: ^testing.T) {
	testing.expect(t, is_locate_type("locate"))
	testing.expect(t, is_locate_type("Locate-Agent"))
	testing.expect(t, !is_locate_type("explore"))
}
