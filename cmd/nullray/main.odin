// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:acp"
import "nullray:app"
import "nullray:config"
import "nullray:constants"
import "nullray:crash"
import "nullray:elevate"
import "nullray:http"
import "nullray:notify"
import "nullray:provider"
import "nullray:run"
import "nullray:sandbox"
import "nullray:selftest"
import "nullray:serve"
import "nullray:ui"

Media_Arg :: struct {
	path: string,
	kind: string,
}

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
	samples:          int,
	architect:        bool,
	trace:            bool,
	stream_print:     bool,
	no_adopt:         bool,
	patch_out:        string,
	acp:              bool,
	serve:            bool,
	connect:          bool,
	attach:           bool,
	watch:            bool,
	watch_args:       [dynamic]string,
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
	media_args:       [dynamic]Media_Arg,
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
	distill:          bool,
	list_modules:     bool,
	probe_tools:      string,
	skills_paths:     string,
	prompt:           string,
	askpass:          bool,
	elevate_broker:   string,
	no_elevate:       bool,
	err:              string,
}

main :: proc() {
	install_pipe_signals()
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
	if cli.no_adopt {
		os.set_env(constants.ENV_ADOPT, "0")
	}
	adopt_notes := config.foreign_adopt()
	defer {
		for n in adopt_notes {
			delete(n)
		}
		delete(adopt_notes)
	}
	for n in adopt_notes {
		fmt.eprintln("nullray: adopt", n)
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
	if cli.watch {
		os.exit(run_watch(cli.watch_args[:]))
	}
	if cli.list_skills {
		os.exit(run_list_skills())
	}
	if cli.distill {
		os.exit(run_distill())
	}
	if cli.list_modules {
		os.exit(run_list_modules())
	}

	if cli.list_models {
		os.exit(run_list_models())
	}
	if len(cli.probe_tools) > 0 {
		os.exit(run_probe_tools(&cli))
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
	elevate.elevate_init(exe, cli.print_mode || cli.acp || cli.serve || cli.connect || cli.attach)
	defer elevate.elevate_shutdown()

	crash.logf("sandbox apply begin")
	provider.cache_api_keys_from_env()
	cfg := sandbox.config_from_env()
	defer sandbox.config_destroy(&cfg)

	// Serve: bind the socket before Landlock applies (MAKE_SOCK is granted
	// nowhere), then grant the socket dir for connect resolve and cleanup
	// unlink. Clients only need the resolve grant.
	serve_fd := -1
	serve_path := ""
	if cli.serve {
		pb := serve.prebind()
		if len(pb.err) > 0 {
			fmt.eprintln("nullray serve:", pb.err)
			serve.prebind_destroy(&pb)
			os.exit(1)
		}
		serve_fd = pb.fd
		serve_path = pb.path
		sock_dir := filepath.dir(serve_path)
		append(&cfg.extra_rw, strings.clone(sock_dir))
		append(&cfg.extra_sock, strings.clone(sock_dir))
	} else if cli.connect || cli.attach || env_truthy(constants.ENV_CONNECT) {
		sock_dir := serve.sock_dir(context.temp_allocator)
		if len(sock_dir) > 0 && os.exists(sock_dir) {
			append(&cfg.extra_sock, strings.clone(sock_dir))
		}
	}

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
	if cli.acp {
		crash.set_note("acp")
		os.exit(run_acp_mode(&cli))
	}
	if cli.serve {
		crash.set_note("serve")
		os.exit(serve.run_serve(serve_fd, serve_path, cli.bare))
	}
	if cli.attach {
		crash.set_note("attach")
		// Positional args after `attach` name the session.
		os.exit(serve.run_attach(cli.prompt))
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

run_acp_mode :: proc(cli: ^Cli) -> int {
	return acp.run_server(cli.bare)
}

env_truthy :: proc(key: string) -> bool {
	v, ok := os.lookup_env(key, context.temp_allocator)
	if !ok {
		return false
	}
	lv := strings.to_lower(v, context.temp_allocator)
	return !(lv == "" || lv == "0" || lv == "false" || lv == "off" || lv == "no")
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

	// --connect / NULLRAY_CONNECT: reuse the warm daemon.
	if cli.connect || env_truthy(constants.ENV_CONNECT) {
		// cwd must outlive the whole RPC exchange, the temp arena can roll
		// over mid-connect, so take an owned copy on the default allocator.
		cwd, _ := os.get_working_directory(context.allocator)
		defer delete(cwd)
		timeout := cli.timeout_sec
		if timeout <= 0 {
			timeout = constants.DEFAULT_PRINT_TIMEOUT_SEC
		}
		return serve.run_print_via_serve(prompt, cwd, timeout)
	}

	media := make([dynamic]run.Media_Input, context.temp_allocator)
	for ma in cli.media_args {
		append(&media, run.Media_Input{path = ma.path, kind = ma.kind})
	}

	rcfg := run.Config{
		prompt = prompt,
		media = media[:],
		output_format = cli.output_format,
		out_path = cli.out_path,
		plan_out = cli.plan_out,
		bare = cli.bare,
		fail_on_findings = cli.fail_on_findings,
		timeout_sec = cli.timeout_sec,
		print_strict = cli.print_strict,
		print_usage = cli.print_usage,
		trace = cli.trace,
		stream_print = cli.stream_print,
		patch_out = cli.patch_out,
		samples = cli.samples,
		architect = cli.architect,
	}
	res := run.run_print(rcfg)
	defer run.result_destroy(&res)
	// A finished print run is the attention bottleneck fix from the
	// parallel-agents literature: tell the user, then emit.
	body := "print run finished"
	if res.exit_code != 0 {
		body = "print run failed"
	}
	notify.notify_send("nullray", body)
	run.emit_result(rcfg, res)
	return res.exit_code
}
