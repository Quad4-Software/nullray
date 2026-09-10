// SPDX-License-Identifier: 0BSD
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:app"
import "nullray:config"
import "nullray:constants"
import "nullray:crash"
import "nullray:elevate"
import "nullray:http"
import "nullray:provider"
import "nullray:run"
import "nullray:sandbox"
import "nullray:selftest"
import "nullray:ui"

Cli :: struct {
	ephemeral:        bool,
	self_test:        bool,
	audit:            bool,
	list_models:      bool,
	list_sessions:    bool,
	inspect_session:  string,
	inspect_follow:   bool,
	inspect_set:      bool,
	show_help:        bool,
	show_version:     bool,
	show_man:         bool,
	show_doctor:      bool,
	debug:            bool,
	no_splash:        bool,
	splash:           bool,
	no_subagents:     bool,
	hide_sensitive:   bool,
	print_strict:     bool,
	print_usage:      bool,
	print_mode:       bool,
	ask_simple:       bool,
	auto:             bool,
	bare:             bool,
	fail_on_findings: bool,
	review_bot:       bool,
	review_staged:    bool,
	review_unstaged:  bool,
	review_untracked: bool,
	review_base:      string,
	review_scope:     string,
	review_paths:     string,
	completions:      string,
	provider:         string,
	model:            string,
	theme:            string,
	mode:             string,
	hunt:             string,
	perms:            string,
	gate:             string,
	sandbox:          string,
	workspace:        string,
	session:          string,
	keys:             string,
	message_file:     string,
	out_path:         string,
	plan_out:         string,
	plan_in:          string,
	output_format:    string,
	timeout_sec:      int,
	search_sessions:  string,
	delete_session:   string,
	rename_session:   string,
	rename_force:     bool,
	export_session:   string,
	import_session:   string,
	as_name:          string,
	list_skills:      bool,
	install_skill:    string,
	uninstall_skill:  string,
	skills_paths:     string,
	prompt:           string,
	askpass:          bool,
	elevate_broker:   string,
	no_elevate:       bool,
	err:              string,
}

main :: proc() {
	cli := parse_cli(os.args[1:])
	if len(cli.err) > 0 {
		fmt.eprintln("nullray:", cli.err)
		os.exit(2)
	}
	if cli.show_help {
		print_help()
		os.exit(0)
	}
	if cli.show_version {
		print_version()
		os.exit(0)
	}
	if cli.show_man {
		print_man()
		os.exit(0)
	}
	if len(cli.completions) > 0 {
		os.exit(print_completions(cli.completions))
	}
	if cli.self_test {
		os.exit(selftest.run())
	}

	apply_cli_env(&cli)

	if _, err := config.load_env_file(); err != "" {
		fmt.eprintln("nullray: config env:", err)
	}
	apply_cli_env(&cli)

	crash.install()
	defer os.exit(0)

	if cli.show_doctor {
		os.exit(crash.doctor())
	}
	if cli.audit {
		os.exit(run_audit())
	}
	if cli.review_bot {
		os.exit(run_review_bot(&cli))
	}

	if cli.list_sessions {
		os.exit(run_list_sessions())
	}
	if cli.inspect_set {
		os.exit(run_inspect_session(&cli))
	}
	if len(cli.search_sessions) > 0 {
		os.exit(run_search_sessions(cli.search_sessions))
	}
	if len(cli.delete_session) > 0 {
		os.exit(run_delete_session(cli.delete_session))
	}
	if len(cli.rename_session) > 0 {
		os.exit(run_rename_session(cli.rename_session, cli.as_name, cli.rename_force))
	}
	if len(cli.export_session) > 0 {
		os.exit(run_export_session(cli.export_session, cli.out_path))
	}
	if len(cli.import_session) > 0 {
		os.exit(run_import_session(cli.import_session, cli.as_name))
	}
	if cli.list_skills {
		os.exit(run_list_skills())
	}
	if len(cli.install_skill) > 0 {
		os.exit(run_install_skill(cli.install_skill, cli.as_name))
	}
	if len(cli.uninstall_skill) > 0 {
		os.exit(run_uninstall_skill(cli.uninstall_skill))
	}

	if cli.list_models {
		os.exit(run_list_models())
	}

	if cli.askpass {
		os.exit(elevate.run_askpass_cli())
	}
	if len(cli.elevate_broker) > 0 {
		os.exit(elevate.run_elevate_broker_server(cli.elevate_broker))
	}

	exe := ""
	if len(os.args) > 0 {
		exe = os.args[0]
	}
	elevate.elevate_init(exe, cli.print_mode)
	defer elevate.elevate_shutdown()

	crash.logf("sandbox apply begin")
	provider.cache_api_keys_from_env()
	cfg := sandbox.config_from_env()
	defer sandbox.config_destroy(&cfg)

	sres := sandbox.apply(cfg)
	if !sres.ok {
		fmt.eprintln("nullray: sandbox failed:", sres.message)
		os.exit(1)
	}
	if len(sres.message) > 0 {
		fmt.eprintln("nullray:", sres.message)
	}
	crash.logf("sandbox ok")

	if !http.global_init() {
		fmt.eprintln("nullray: TLS init failed")
		os.exit(1)
	}
	defer http.global_cleanup()
	crash.logf("http ok")

	if cli.print_mode {
		crash.set_note("print-mode")
		os.exit(run_print_mode(&cli))
	}

	color := env_or(constants.ENV_COLOR, "")
	theme := env_or(constants.ENV_THEME, "ink")

	resume_name: string
	defer {
		if len(resume_name) > 0 {
			fmt.printf("To resume this session: nullray --session %s\n", resume_name)
			delete(resume_name)
		}
	}

	loop: ui.Loop
	if !ui.loop_init(&loop, color, theme) {
		fmt.eprintln("nullray: terminal init failed (need a TTY)")
		fmt.eprintln("nullray: tip: run `nullray --self-test` for a headless smoke check")
		fmt.eprintln("nullray: tip: use `nullray --print \"prompt\"` for one-shot agent runs")
		fmt.eprintln("nullray: tip: run `nullray --doctor` for env and crash dump paths")
		os.exit(1)
	}
	defer ui.loop_close(&loop)
	crash.logf("terminal ok %dx%d", loop.term.width, loop.term.height)

	a: app.App
	app.app_init(&a, &loop)
	defer app.app_destroy(&a)
	crash.set_session(a.session.name)
	provider.set_session(a.session.name)
	crash.set_note("tui")
	crash.logf("app ready session=%s", a.session.name)

	ui.loop_run(&loop, app.app_draw, app.app_on_event, &a, app.app_is_dirty, app.app_on_tick)
	if a.session.persist && len(a.session.name) > 0 {
		resume_name = strings.clone(a.session.name)
	}
}

run_print_mode :: proc(cli: ^Cli) -> int {
	want_stdin := !run.stdin_is_tty()
	prompt, perr := run.build_prompt(cli.prompt, cli.message_file, want_stdin)
	if len(perr) > 0 {
		fmt.eprintln("nullray:", perr)
		delete(perr)
		return 2
	}
	defer delete(prompt)

	rcfg := run.Config{
		prompt = prompt,
		output_format = cli.output_format,
		out_path = cli.out_path,
		plan_out = cli.plan_out,
		bare = cli.bare,
		fail_on_findings = cli.fail_on_findings,
		timeout_sec = cli.timeout_sec,
		print_strict = cli.print_strict,
		print_usage = cli.print_usage,
	}
	res := run.run_print(rcfg)
	defer run.result_destroy(&res)
	run.emit_result(rcfg, res)
	return res.exit_code
}
