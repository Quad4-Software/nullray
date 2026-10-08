// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_term_write_cup_format :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.allocator)
	defer strings.builder_destroy(&b)
	term_write_cup(&b, 12, 34)
	testing.expect_value(t, strings.to_string(b), "\x1b[12;34H")
	strings.builder_reset(&b)
	term_write_cup(&b, 1, 1)
	testing.expect_value(t, strings.to_string(b), "\x1b[1;1H")
}

@(test)
test_diff_scan_throughput :: proc(t: ^testing.T) {
	// Microbench the cell equality path used by term_present diffs.
	w, h := 120, 40
	buf := buffer_create(w, h)
	defer buffer_destroy(&buf)
	prev := buffer_create(w, h)
	defer buffer_destroy(&prev)
	buffer_clear(&buf, Color{10, 10, 12}, Color{200, 200, 200})
	copy(prev.cells, buf.cells)

	t0 := time.tick_now()
	changed := 0
	frames := 200
	for i in 0 ..< frames {
		buf.cells[i % len(buf.cells)].ch = rune('A' + i % 26)
		for y in 0 ..< h {
			row := y * w
			for x in 0 ..< w {
				idx := row + x
				c := buf.cells[idx]
				p := prev.cells[idx]
				if c.ch == p.ch &&
					c.fg.r == p.fg.r && c.fg.g == p.fg.g && c.fg.b == p.fg.b &&
					c.bg.r == p.bg.r && c.bg.g == p.bg.g && c.bg.b == p.bg.b &&
					c.style == p.style {
					continue
				}
				changed += 1
				prev.cells[idx] = c
			}
		}
	}
	ns := time.duration_nanoseconds(time.tick_since(t0))
	testing.expect(t, changed == frames)
	// 200 frames of 120x40 scans should stay under 100ms on normal hosts.
	testing.expect(t, ns < 100_000_000)
}
