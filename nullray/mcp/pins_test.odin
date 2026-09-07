// SPDX-License-Identifier: 0BSD
package mcp

import "core:testing"
import "nullray:tools"

@(test)
test_tools_fingerprint_tracks_schema_drift :: proc(t: ^testing.T) {
	first := []tools.Tool{{
		name = "mcp:test:read",
		description = "read data",
		schema_json = `{"type":"object"}`,
	}}
	second := []tools.Tool{{
		name = "mcp:test:read",
		description = "read data",
		schema_json = `{"type":"object","required":["path"]}`,
	}}
	a := tools_fingerprint("test", first)
	defer delete(a)
	b := tools_fingerprint("test", second)
	defer delete(b)
	testing.expect(t, a != b)
}
