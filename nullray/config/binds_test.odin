// SPDX-License-Identifier: 0BSD
package config

import "core:testing"
import "nullray:ui"

@(test)
test_binds_resolve_stop_agent_default :: proc(t: ^testing.T) {
	b := binds_defaults()
	testing.expect_value(t, b.stop_agent, ui.Key.Esc)
	testing.expect_value(t, binds_resolve(b, .Esc), Action.Stop_Agent)
	testing.expect_value(t, binds_resolve(b, .F3), Action.Pause_Agent)
}

@(test)
test_binds_resolve_stop_agent_remap :: proc(t: ^testing.T) {
	b := binds_defaults()
	b.stop_agent = .F4
	testing.expect_value(t, binds_resolve(b, .F4), Action.Stop_Agent)
	testing.expect_value(t, binds_resolve(b, .Esc), Action.None)
}

@(test)
test_binds_resolve_ctrl_c_quit :: proc(t: ^testing.T) {
	b := binds_defaults()
	testing.expect_value(t, binds_resolve(b, .Ctrl_C), Action.Quit)
}

@(test)
test_binds_presets_keep_stop :: proc(t: ^testing.T) {
	n := binds_neovim()
	e := binds_emacs()
	testing.expect_value(t, binds_resolve(n, .Esc), Action.Stop_Agent)
	testing.expect_value(t, binds_resolve(e, .Esc), Action.Stop_Agent)
}
