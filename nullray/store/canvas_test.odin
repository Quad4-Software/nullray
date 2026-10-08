// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package store

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_canvas_save_load_roundtrip :: proc(t: ^testing.T) {
	schema := `{"title":"Board","placement":"panel","fields":[{"id":"x","type":"text","default":"hi"}]}`
	id, err := canvas_save("unit-board", "Board", schema)
	testing.expect_value(t, err, "")
	defer {
		_ = canvas_delete(id)
		delete(id)
	}
	testing.expect(t, len(id) > 0)

	got, title, lerr := canvas_load(id)
	testing.expect_value(t, lerr, "")
	defer delete(got)
	defer delete(title)
	testing.expect(t, strings.contains(got, `"placement"`) || strings.contains(got, "panel"))
	testing.expect(t, strings.contains(got, "Board") || len(title) > 0)
}

@(test)
test_canvas_corrupt_rejected :: proc(t: ^testing.T) {
	ensure_canvas_dir()
	path := canvas_path("bad-unit", context.temp_allocator)
	_ = os.write_entire_file(path, transmute([]u8)string(`{"no":"magic"}`))
	defer os.remove(path)
	_, _, err := canvas_load("bad-unit")
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "corrupt") || strings.contains(err, "magic"))
	delete(err)
}

@(test)
test_canvas_invalid_schema_rejected :: proc(t: ^testing.T) {
	_, err := canvas_save("x", "x", "not-json")
	testing.expect(t, len(err) > 0)
	delete(err)
}
