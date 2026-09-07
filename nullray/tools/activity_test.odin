// SPDX-License-Identifier: 0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_tool_activity_shell :: proc(t: ^testing.T) {
	line := tool_activity_line("run_shell", `{"command":"make test"}`, context.temp_allocator)
	testing.expect(t, strings.contains(line, "running run_shell"))
	testing.expect(t, strings.contains(line, "make test"))
}

@(test)
test_tool_activity_path :: proc(t: ^testing.T) {
	line := tool_activity_line("write_file", `{"path":"openmeteo_weather.py","content":"x"}`, context.temp_allocator)
	testing.expect(t, strings.contains(line, "write_file"))
	testing.expect(t, strings.contains(line, "openmeteo_weather.py"))
}
