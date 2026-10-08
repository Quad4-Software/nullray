// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:ui"

@(test)
test_set_tui_get_and_session_set :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_UI_MALLEABLE, context.temp_allocator)
	defer if had {
		os.set_env(constants.ENV_UI_MALLEABLE, prev)
	} else {
		os.unset_env(constants.ENV_UI_MALLEABLE)
	}
	os.unset_env(constants.ENV_UI_MALLEABLE)

	out, err := tool_set_tui(`{"action":"get"}`)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(out, "colors"))
	delete(out)

	out2, err2 := tool_set_tui(`{"action":"set","scope":"session","theme":"ember","accent":"#00ffcc"}`)
	testing.expect_value(t, err2, "")
	testing.expect(t, strings.contains(out2, `"ok":true`))
	delete(out2)
	testing.expect_value(t, ui.theme().name, "custom")
	testing.expect_value(t, ui.theme().accent.g, u8(255))

	out3, err3 := tool_set_tui(`{"action":"reset"}`)
	testing.expect_value(t, err3, "")
	delete(out3)
}

@(test)
test_set_tui_disabled :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_UI_MALLEABLE, context.temp_allocator)
	defer if had {
		os.set_env(constants.ENV_UI_MALLEABLE, prev)
	} else {
		os.unset_env(constants.ENV_UI_MALLEABLE)
	}
	os.set_env(constants.ENV_UI_MALLEABLE, "0")
	out, err := tool_set_tui(`{"action":"get"}`)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "disabled"))
	delete(out)
	delete(err)
}

@(test)
test_show_view_disabled :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_UI_MALLEABLE, context.temp_allocator)
	defer if had {
		os.set_env(constants.ENV_UI_MALLEABLE, prev)
	} else {
		os.unset_env(constants.ENV_UI_MALLEABLE)
	}
	os.set_env(constants.ENV_UI_MALLEABLE, "0")
	out, err := tool_show_view(`{"title":"x"}`)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "disabled"))
	delete(out)
	delete(err)
}

@(test)
test_set_tui_global_lock :: proc(t: ^testing.T) {
	prev_m, had_m := os.lookup_env(constants.ENV_UI_MALLEABLE, context.temp_allocator)
	prev_l, had_l := os.lookup_env(constants.ENV_UI_LOCK, context.temp_allocator)
	defer {
		if had_m {
			os.set_env(constants.ENV_UI_MALLEABLE, prev_m)
		} else {
			os.unset_env(constants.ENV_UI_MALLEABLE)
		}
		if had_l {
			os.set_env(constants.ENV_UI_LOCK, prev_l)
		} else {
			os.unset_env(constants.ENV_UI_LOCK)
		}
	}
	os.unset_env(constants.ENV_UI_MALLEABLE)
	os.set_env(constants.ENV_UI_LOCK, "1")
	out, err := tool_set_tui(`{"scope":"global","theme":"ink"}`)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "lock"))
	delete(out)
	delete(err)
}
