// SPDX-License-Identifier: 0BSD
/*
Headless startup and drawing smoke checks (no TTY).
*/

package selftest

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:http"
import "nullray:mcp"
import "nullray:sandbox"
import "nullray:store"
import "nullray:tools"
import "nullray:ui"

run :: proc() -> int {
	fails := 0

	tools_reg: tools.Registry
	tools.registry_init(&tools_reg)
	defer tools.registry_destroy(&tools_reg)
	if len(tools.registry_list(&tools_reg)) == 0 {
		fmt.eprintln("selftest: no built-in tools registered")
		fails += 1
	}

	mcp_reg: mcp.Registry
	mcp.registry_init(&mcp_reg, &tools_reg)
	defer mcp.registry_destroy(&mcp_reg)
	mcp.mcp_autoload(&mcp_reg)

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

	os.unset_env(constants.ENV_SECRETS_ALLOW)
	if !sandbox.path_is_secret_blocked("/tmp/nullray-selftest/.env") {
		fmt.eprintln("selftest: .env should be secret-blocked")
		fails += 1
	}

	os.set_env(constants.ENV_OPS, "docker")
	ops_cfg := sandbox.config_from_env()
	if !ops_cfg.keep_docker_host || len(ops_cfg.extra_sock) == 0 {
		fmt.eprintln("selftest: NULLRAY_OPS=docker should grant docker sock")
		fails += 1
	}
	sandbox.config_destroy(&ops_cfg)
	os.unset_env(constants.ENV_OPS)

	blocked, _ := tools.fetch_url_blocked("http://127.0.0.1/")
	if !blocked {
		fmt.eprintln("selftest: fetch_url should block loopback")
		fails += 1
	}

	os.set_env(constants.ENV_PRIVACY_REDACT, "1")
	os.set_env("HOME", "/home/user1")
	os.set_env("USER", "user1")
	redacted := sandbox.redact_secrets("see /home/user1/secret")
	if strings.contains(redacted, "/home/user1") {
		fmt.eprintln("selftest: redact_secrets left HOME path")
		fails += 1
	}
	delete(redacted)

	if fails == 0 {
		fmt.println("nullray: self-test ok")
		return 0
	}
	fmt.eprintf("nullray: self-test failed (%d)\n", fails)
	return 1
}
