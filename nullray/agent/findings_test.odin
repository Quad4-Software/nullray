// SPDX-License-Identifier: 0BSD
package agent

import "core:strings"
import "core:testing"

@(test)
test_parse_findings_list_and_json :: proc(t: ^testing.T) {
	text := "high|src/a.py:3|sql concat\nwarn|b.js|xss\n\nFINDINGS: 2\n"
	items := parse_findings_list(text)
	defer findings_destroy(items)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].severity, "high")
	testing.expect_value(t, items[0].path, "src/a.py")
	testing.expect_value(t, items[0].line, 3)
	n, found := parse_findings_trailer(text)
	testing.expect(t, found)
	testing.expect_value(t, n, 2)
	js := findings_to_json(items, n, found)
	defer delete(js)
	testing.expect(t, strings.contains(js, `"count":2`))
	testing.expect(t, strings.contains(js, `"path":"src/a.py"`))
}

@(test)
test_parse_findings_list_oracle_section_only :: proc(t: ^testing.T) {
	text := "high|explore/old.py:1|stale lead\n\n--- hunt oracle ---\n\nhigh|src/a.py:3|confirmed\n\nFINDINGS: 1\n"
	items := parse_findings_list(text)
	defer findings_destroy(items)
	testing.expect_value(t, len(items), 1)
	testing.expect_value(t, items[0].path, "src/a.py")
}

@(test)
test_parse_findings_coderabbit_severities :: proc(t: ^testing.T) {
	text := "critical|a.c:1|overflow\nmajor|b.go:2|race\nminor|c.ts|nit\n\nFINDINGS: 3\n"
	items := parse_findings_list(text)
	defer findings_destroy(items)
	testing.expect_value(t, len(items), 3)
	blocks, total := parse_block_findings(text)
	testing.expect_value(t, total, 3)
	testing.expect_value(t, blocks, 2)
	testing.expect(t, finding_is_blocking("critical"))
	testing.expect(t, !finding_is_blocking("info"))
}
