// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package mcp

import "core:strings"
import "core:testing"

@(test)
test_stdio_take_line_batches :: proc(t: ^testing.T) {
	s: Stdio_Session
	defer delete(s.pending)
	append(&s.pending, ..transmute([]u8)string(`{"id":1}` + "\n" + `{"id":2}` + "\n" + `{"id"`))

	line, ok := stdio_take_line(&s)
	testing.expect(t, ok)
	testing.expect(t, line == `{"id":1}`)
	delete(line)

	line2, ok2 := stdio_take_line(&s)
	testing.expect(t, ok2)
	testing.expect(t, line2 == `{"id":2}`)
	delete(line2)

	// Third frame is incomplete and stays buffered for the next read.
	_, ok3 := stdio_take_line(&s)
	testing.expect(t, !ok3)
	testing.expect(t, len(s.pending) == 5)

	append(&s.pending, ':', '4', '}', '\n')
	line4, ok4 := stdio_take_line(&s)
	testing.expect(t, ok4)
	testing.expect(t, line4 == `{"id":4}`)
	delete(line4)
	testing.expect(t, len(s.pending) == 0)
}

@(test)
test_stdio_take_line_empty_line :: proc(t: ^testing.T) {
	s: Stdio_Session
	defer delete(s.pending)
	append(&s.pending, '\n')
	line, ok := stdio_take_line(&s)
	testing.expect(t, ok)
	testing.expect(t, len(line) == 0)
	delete(line)
	testing.expect(t, len(s.pending) == 0)
}
