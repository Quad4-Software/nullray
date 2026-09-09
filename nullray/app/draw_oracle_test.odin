// SPDX-License-Identifier: 0BSD
package app

import "core:os"
import "core:testing"
import "nullray:constants"
import "nullray:ui"

@(test)
test_layout_frozen_count_idle :: proc(t: ^testing.T) {
	a: App
	blocks := make([]Transcript_Block, 3, context.temp_allocator)
	n := layout_frozen_count(&a, blocks)
	testing.expect_value(t, n, 3)
}

@(test)
test_layout_cache_width_busts :: proc(t: ^testing.T) {
	a: App
	a.layout_cache.valid = true
	a.layout_cache.width = 80
	a.layout_cache.theme_accent = ui.INK.accent
	a.layout_cache.msg_count = 0
	testing.expect(t, layout_cache_key_match(&a, 80, ui.INK.accent))
	testing.expect(t, !layout_cache_key_match(&a, 100, ui.INK.accent))
	app_layout_cache_clear(&a)
}

@(test)
test_view_auto_from_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_VIEW_AUTO)
	testing.expect(t, view_auto_from_env())
	os.set_env(constants.ENV_VIEW_AUTO, "0")
	testing.expect(t, !view_auto_from_env())
	os.unset_env(constants.ENV_VIEW_AUTO)
}
