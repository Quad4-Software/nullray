/*
Headless startup and drawing smoke checks (no TTY).
*/

package selftest

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:http"
import "nullray:mcp"
import "nullray:store"
import "nullray:tools"
import "nullray:ui"

run :: proc() -> int {
	fails := 0

	tools.tools_init()
	defer tools.tools_destroy()
	if len(tools.list()) == 0 {
		fmt.eprintln("selftest: no built-in tools registered")
		fails += 1
	}

	mcp.mcp_init()
	defer mcp.mcp_destroy()
	mcp.mcp_autoload()

	if !http.global_init() {
		fmt.eprintln("selftest: curl init failed")
		fails += 1
	} else {
		http.global_cleanup()
	}

	ui.theme_set(ui.theme_by_name("ink"))
	buf := ui.buffer_create(48, 12)
	defer ui.buffer_destroy(&buf)
	ui.draw_status_bar(&buf, 0, "nullray", constants.VERSION, ui.theme().title, ui.theme().status_bg)
	ui.draw_input_line(&buf, 11, "> ", "hello", 5, ui.theme().fg, ui.theme().input_bg, ui.theme().accent)
	if ui.buffer_at(&buf, 1, 0) == nil || ui.buffer_at(&buf, 1, 0).ch != 'n' {
		fmt.eprintln("selftest: status bar draw failed")
		fails += 1
	}
	if ui.buffer_at(&buf, 1, 11) == nil || ui.buffer_at(&buf, 1, 11).ch != '>' {
		fmt.eprintln("selftest: input line draw failed")
		fails += 1
	}

	ok, reason := tools.shell_command_allowed("rm -rf /")
	if ok {
		fmt.eprintln("selftest: dangerous shell should be denied")
		fails += 1
	}
	delete(reason)

	name := store.sanitize_name("x y")
	if name != "x_y" {
		fmt.eprintln("selftest: sanitize_name failed:", name)
		fails += 1
	}

	req := mcp.build_request(1, "initialize", `{}`)
	defer delete(req)
	if !strings.contains(req, "initialize") {
		fmt.eprintln("selftest: jsonrpc build failed")
		fails += 1
	}

	if fails == 0 {
		fmt.println("nullray: self-test ok")
		return 0
	}
	fmt.eprintf("nullray: self-test failed (%d)\n", fails)
	return 1
}
