// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package art

import "core:strings"
import "core:testing"

@(test)
test_figlet_contains_ink :: proc(t: ^testing.T) {
	s := art_figlet("AB", false, context.allocator)
	defer delete(s)
	testing.expect(t, strings.contains(s, "#"))
	testing.expect(t, strings.contains(s, "\n"))
}

@(test)
test_render_plot_and_bars :: proc(t: ^testing.T) {
	prog := `{"width":40,"height":12,"unicode":false,"ops":[
	  {"op":"figlet","text":"OK","x":0,"y":0},
	  {"op":"plot","fn":"sin","x":0,"y":5,"w":20,"h":6},
	  {"op":"bars","x":22,"y":5,"h":6,"values":[1,2,3,2]}
	]}`
	plain, _, err := art_render_json(prog, context.allocator)
	defer delete(plain)
	testing.expect_value(t, err, "")
	testing.expect(t, len(plain) > 20)
	testing.expect(t, strings.contains(plain, "#") || strings.contains(plain, "-") || strings.contains(plain, "|") || strings.contains(plain, "+"))
}

@(test)
test_ansi_blit_green :: proc(t: ^testing.T) {
	prog := "{\"width\":10,\"height\":3,\"ops\":[{\"op\":\"ansi\",\"text\":\"\\u001b[32mHI\\u001b[0m\",\"x\":0,\"y\":0\"}]}"
	// hand escape
	prog2 := "{\"width\":10,\"height\":3,\"ops\":[{\"op\":\"ansi\",\"text\":\"ESC[32mHIESC[0m\"}]}"
	_ = prog2
	raw := "\x1b[32mHI\x1b[0m"
	c := canvas_create(10, 3, true)
	defer canvas_destroy(&c)
	_ = ansi_blit(&c, raw, 0, 0)
	testing.expect_value(t, c.cells[0].ch, 'H')
	testing.expect_value(t, c.cells[1].ch, 'I')
	testing.expect(t, c.cells[0].has_fg)
}
