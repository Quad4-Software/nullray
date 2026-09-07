// SPDX-License-Identifier: 0BSD
/*
Lifecycle: init secret channel, optional broker, teardown.
*/

package elevate

import "core:os"
import "core:strings"

elevate_init :: proc(exe_path: string, headless_mode: bool) {
	secret_init()
	set_headless(headless_mode)
	secret_set_ui_enabled(!headless_mode)
	if len(exe_path) > 0 {
		set_self_exe(exe_path)
	} else if len(os.args) > 0 {
		set_self_exe(os.args[0])
	}
	when ODIN_OS != .Windows {
		_ = broker_start(self_exe())
	}
	g_started = true
}

elevate_shutdown :: proc() {
	clear_askpass_secret()
	when ODIN_OS != .Windows {
		broker_stop()
	}
	if len(g_self_exe) > 0 {
		delete(g_self_exe)
		g_self_exe = {}
	}
	g_started = false
}

elevate_started :: proc() -> bool {
	return g_started
}
