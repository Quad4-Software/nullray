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
import "nullray:secure"
import "nullray:selftest"
import "nullray:session"
import "nullray:skills"
import "nullray:store"
import "nullray:ui"

Cli :: struct {
	ephemeral:        bool,
	self_test:        bool,
	audit:            bool,
	list_models:      bool,
	list_sessions:    bool,
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
	completions:      string,
	provider:         string,
	model:            string,
	theme:            string,
	mode:             string,
	perms:            string,
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

	if cli.list_sessions {
		os.exit(run_list_sessions())
	}
	if len(cli.search_sessions) > 0 {
		os.exit(run_search_sessions(cli.search_sessions))
	}
	if len(cli.delete_session) > 0 {
		os.exit(run_delete_session(cli.delete_session))
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

parse_cli :: proc(args: []string) -> Cli {
	cli: Cli
	prompt_parts := make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(args) {
		arg := args[i]
		switch arg {
		case "--help", "-h":
			cli.show_help = true
		case "--version", "-V":
			cli.show_version = true
		case "--man":
			cli.show_man = true
		case "--ephemeral", "-e":
			cli.ephemeral = true
		case "--self-test", "-t":
			cli.self_test = true
		case "--audit":
			cli.audit = true
		case "--doctor":
			cli.show_doctor = true
		case "--debug":
			cli.debug = true
		case "--list-models":
			cli.list_models = true
		case "--list-sessions":
			cli.list_sessions = true
		case "--search-sessions":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--search-sessions needs a query"
				return cli
			}
			cli.search_sessions = v
		case "--delete-session":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--delete-session needs a name"
				return cli
			}
			cli.delete_session = v
		case "--export-session":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--export-session needs a name"
				return cli
			}
			cli.export_session = v
		case "--import-session":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--import-session needs a path"
				return cli
			}
			cli.import_session = v
		case "--as":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--as needs a session or skill name"
				return cli
			}
			cli.as_name = v
		case "--list-skills":
			cli.list_skills = true
		case "--install-skill":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--install-skill needs a path"
				return cli
			}
			cli.install_skill = v
		case "--uninstall-skill":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--uninstall-skill needs a skill id"
				return cli
			}
			cli.uninstall_skill = v
		case "--skills":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--skills needs a path or path list"
				return cli
			}
			if len(cli.skills_paths) > 0 {
				next := fmt.aprintf("%s,%s", cli.skills_paths, v)
				delete(cli.skills_paths)
				cli.skills_paths = next
			} else {
				cli.skills_paths = strings.clone(v)
			}
		case "--print", "-P":
			cli.print_mode = true
		case "-q", "--ask":
			cli.print_mode = true
			cli.ask_simple = true
		case "--bare":
			cli.bare = true
		case "--fail-on-findings":
			cli.fail_on_findings = true
		case "--provider", "-p":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--provider needs a value"
				return cli
			}
			cli.provider = v
		case "--model", "-m":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--model needs a value"
				return cli
			}
			cli.model = v
		case "--theme":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--theme needs a value"
				return cli
			}
			cli.theme = v
		case "--mode":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--mode needs a value"
				return cli
			}
			cli.mode = v
		case "--perms":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--perms needs a value"
				return cli
			}
			cli.perms = v
		case "--askpass":
			cli.askpass = true
		case "--elevate-broker":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--elevate-broker needs a path"
				return cli
			}
			cli.elevate_broker = v
		case "--no-elevate":
			cli.no_elevate = true
		case "--sandbox":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--sandbox needs a value"
				return cli
			}
			cli.sandbox = v
		case "--workspace", "-w":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--workspace needs a value"
				return cli
			}
			cli.workspace = v
		case "--session":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--session needs a value"
				return cli
			}
			cli.session = v
		case "--keys":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--keys needs default|neovim|emacs"
				return cli
			}
			if _, pok := config.preset_from_name(v); !pok {
				cli.err = "--keys needs default|neovim|emacs"
				return cli
			}
			cli.keys = v
		case "--message-file":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--message-file needs a path"
				return cli
			}
			cli.message_file = v
		case "--out":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--out needs a path"
				return cli
			}
			cli.out_path = v
		case "--plan-out":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--plan-out needs a path"
				return cli
			}
			cli.plan_out = v
		case "--plan-in":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--plan-in needs a path"
				return cli
			}
			cli.plan_in = v
		case "--output-format":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--output-format needs text|json"
				return cli
			}
			lv := strings.to_lower(v, context.temp_allocator)
			if lv != "text" && lv != "json" {
				cli.err = "--output-format needs text|json"
				return cli
			}
			cli.output_format = lv
		case "--timeout":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--timeout needs seconds"
				return cli
			}
			n, nok := parse_cli_int(v)
			if !nok || n <= 0 {
				cli.err = "--timeout needs a positive integer (seconds)"
				return cli
			}
			cli.timeout_sec = n
		case "--no-splash":
			cli.no_splash = true
		case "--no-subagents":
			cli.no_subagents = true
		case "--splash":
			cli.splash = true
		case "--hide-sensitive":
			cli.hide_sensitive = true
		case "--print-strict":
			cli.print_strict = true
		case "--auto":
			cli.auto = true
		case "--usage":
			cli.print_usage = true
		case "--completions":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--completions needs a shell name"
				return cli
			}
			cli.completions = v
		case:
			if strings.has_prefix(arg, "-") {
				cli.err = fmt.aprintf("unknown flag: %s", arg)
				return cli
			}
			append(&prompt_parts, arg)
		}
		i += 1
	}
	if len(prompt_parts) > 0 {
		cli.prompt = strings.join(prompt_parts[:], " ", context.allocator)
	}
	if len(cli.plan_in) > 0 && len(cli.plan_out) > 0 {
		cli.err = "plan-in and plan-out cannot be used together"
	}
	return cli
}

@(private)
parse_cli_int :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 {
		return 0, false
	}
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}

take_value :: proc(args: []string, i: ^int) -> (string, bool) {
	if i^ + 1 >= len(args) {
		return "", false
	}
	i^ += 1
	return args[i^], true
}

apply_cli_env :: proc(cli: ^Cli) {
	if len(cli.plan_in) > 0 {
		os.set_env(constants.ENV_PLAN_IN, cli.plan_in)
	}
	if cli.print_mode {
		os.set_env(constants.ENV_PRINT, "1")
		if !cli.ephemeral && len(cli.session) == 0 {
			os.set_env(constants.ENV_EPHEMERAL, "1")
		}
		if cli.ask_simple {
			os.set_env(constants.ENV_ASK_SIMPLE, "1")
			if len(cli.mode) == 0 {
				os.set_env(constants.ENV_MODE, "ask")
			}
			if len(cli.perms) == 0 {
				if _, ok := os.lookup_env(constants.ENV_PERMS, context.temp_allocator); !ok {
					os.set_env(constants.ENV_PERMS, "ask")
				}
			}
		} else if len(cli.mode) == 0 {
			if _, ok := os.lookup_env(constants.ENV_MODE, context.temp_allocator); !ok {
				has_plan_in := len(cli.plan_in) > 0
				if !has_plan_in {
					if v, pok := os.lookup_env(constants.ENV_PLAN_IN, context.temp_allocator); pok && len(v) > 0 {
						has_plan_in = true
					}
				}
				if has_plan_in {
					os.set_env(constants.ENV_MODE, "edit")
				} else {
					os.set_env(constants.ENV_MODE, "ask")
				}
			}
		}
	}
	if cli.ephemeral {
		os.set_env(constants.ENV_EPHEMERAL, "1")
	}
	if cli.bare {
		os.set_env(constants.ENV_BARE, "1")
	}
	if len(cli.skills_paths) > 0 {
		os.set_env(constants.ENV_SKILLS, cli.skills_paths)
	}
	if cli.fail_on_findings {
		os.set_env(constants.ENV_FAIL_ON_FINDINGS, "1")
	}
	if len(cli.provider) > 0 {
		os.set_env(constants.ENV_PROVIDER, cli.provider)
	}
	if len(cli.model) > 0 {
		os.set_env(constants.ENV_MODEL, cli.model)
	}
	if len(cli.theme) > 0 {
		os.set_env(constants.ENV_THEME, cli.theme)
	}
	if len(cli.mode) > 0 {
		os.set_env(constants.ENV_MODE, cli.mode)
	}
	if len(cli.perms) > 0 {
		os.set_env(constants.ENV_PERMS, cli.perms)
	}
	if len(cli.sandbox) > 0 {
		os.set_env(constants.ENV_SANDBOX, cli.sandbox)
	}
	if cli.no_elevate {
		os.set_env(constants.ENV_ELEVATE, "deny")
	}
	if len(cli.workspace) > 0 {
		os.set_env(constants.ENV_WORKSPACE, cli.workspace)
	}
	if len(cli.session) > 0 {
		os.set_env(constants.ENV_SESSION, cli.session)
	}
	if len(cli.keys) > 0 {
		os.set_env(constants.ENV_KEYS, cli.keys)
	}
	if len(cli.out_path) > 0 {
		os.set_env(constants.ENV_OUT, cli.out_path)
	}
	if len(cli.plan_out) > 0 {
		os.set_env(constants.ENV_PLAN_OUT, cli.plan_out)
	}
	if len(cli.output_format) > 0 {
		os.set_env(constants.ENV_OUTPUT_FORMAT, cli.output_format)
	}
	if cli.timeout_sec > 0 {
		os.set_env(constants.ENV_PRINT_TIMEOUT, fmt.tprintf("%d", cli.timeout_sec))
	}
	if len(cli.message_file) > 0 {
		os.set_env(constants.ENV_MESSAGE_FILE, cli.message_file)
	}
	if cli.no_splash {
		os.set_env(constants.ENV_SPLASH, "0")
	} else if cli.splash {
		os.set_env(constants.ENV_SPLASH, "1")
	}
	if cli.no_subagents {
		os.set_env(constants.ENV_SUBAGENTS, "0")
	}
	if cli.hide_sensitive {
		os.set_env(constants.ENV_HIDE_SENSITIVE, "1")
	}
	if cli.print_strict {
		os.set_env(constants.ENV_PRINT_STRICT, "1")
	}
	if cli.auto {
		os.set_env(constants.ENV_AUTO, "1")
	}
	if cli.print_usage {
		os.set_env(constants.ENV_PRINT_USAGE, "1")
	}
	if cli.debug {
		os.set_env(constants.ENV_DEBUG, "1")
	}
}

run_list_models :: proc() -> int {
	if !http.global_init() {
		fmt.eprintln("nullray: TLS init failed")
		return 1
	}
	defer http.global_cleanup()

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	p := provider.registry_active(&reg)
	if p == nil || p.list_models == nil {
		fmt.eprintln("nullray: no provider with list_models")
		return 1
	}
	fmt.printf("%s (%s) models via %s\n", p.name, p.id, p.base_url)
	models, err := p.list_models(p)
	if len(err) > 0 {
		fmt.eprintln("nullray: list-models:", err)
		return 1
	}
	defer provider.destroy_models(models)
	if len(models) == 0 {
		fmt.println("(none)")
		return 0
	}
	for m in models {
		fmt.println(m.id)
	}
	return 0
}

run_list_sessions :: proc() -> int {
	text := session.session_list_text()
	defer delete(text)
	fmt.println(text)
	return 0
}

run_search_sessions :: proc(query: string) -> int {
	text := session.session_search_text(query)
	defer delete(text)
	fmt.println(text)
	return 0
}

run_delete_session :: proc(name: string) -> int {
	ok, err := store.delete_session(name)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("deleted session %s\n", store.sanitize_name(name))
	return 0
}

run_export_session :: proc(name: string, out_dir: string) -> int {
	if len(strings.trim_space(out_dir)) == 0 {
		fmt.eprintln("nullray: --export-session needs --out DIR")
		return 2
	}
	ok, err := store.export_session(name, out_dir)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("exported session %s to %s\n", store.sanitize_name(name), out_dir)
	return 0
}

run_import_session :: proc(src: string, as_name: string) -> int {
	name, ok, err := store.import_session(src, as_name)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("imported session %s\n", name)
	fmt.printf("To resume this session: nullray --session %s\n", name)
	return 0
}

run_list_skills :: proc() -> int {
	text := skills.skills_list_text()
	defer delete(text)
	fmt.println(text)
	return 0
}

run_install_skill :: proc(src: string, as_name: string) -> int {
	id, dest, err := skills.install_skill(src, as_name)
	if len(err) > 0 {
		fmt.eprintln("nullray:", err)
		delete(err)
		return 1
	}
	defer delete(id)
	defer delete(dest)
	fmt.printf("installed skill %s -> %s\n", id, dest)
	return 0
}

run_uninstall_skill :: proc(id: string) -> int {
	ok, err := skills.uninstall_skill(id)
	if !ok {
		fmt.eprintln("nullray:", err)
		delete(err)
		return 1
	}
	fmt.printf("uninstalled skill %s\n", skills.sanitize_skill_id(id, context.temp_allocator))
	return 0
}

run_audit :: proc() -> int {
	root := env_or(constants.ENV_WORKSPACE, "")
	if len(root) == 0 {
		cwd, err := os.get_working_directory(context.temp_allocator)
		if err != nil {
			fmt.eprintln("nullray: audit: cannot resolve workspace")
			return 2
		}
		root = cwd
	}
	text := secure.audit_all(root)
	defer delete(text)
	fmt.println(text)
	if secure.has_high(text) {
		return 1
	}
	return 0
}

print_version :: proc() {
	fmt.printf("%s %s (built %s %s)\n", constants.APP_NAME, constants.VERSION, constants.BUILD_DATE, constants.BUILD_TIME)
}

print_help :: proc() {
	print_version()
	fmt.println("usage: nullray [options] [prompt...]")
	fmt.println("")
	fmt.println("options:")
	fmt.println("  -h, --help              show this help")
	fmt.println("  -V, --version           show version and build stamp")
	fmt.println("  -e, --ephemeral         do not load or save session transcripts")
	fmt.println("  -t, --self-test         headless smoke (tools, mcp, draw, shell deny)")
	fmt.println("      --audit             run workspace security scanners and exit")
	fmt.println("      --doctor            print env, TTY, and latest crash dump path")
	fmt.println("      --debug             verbose stderr logs (also NULLRAY_DEBUG=1)")
	fmt.println("  -P, --print             one-shot agent (no TUI), print reply and exit")
	fmt.println("  -q, --ask               simple Q&A (print + ask + ephemeral, read-only tools)")
	fmt.println("  -p, --provider ID       ollama | lmstudio | openai | openai-compat |")
	fmt.println("                          openrouter | opencode | opencode-go |")
	fmt.println("                          anthropic | gemini | groq | deepseek |")
	fmt.println("                          mistral | together | fireworks | xai | azure")
	fmt.println("  -m, --model NAME        override default model")
	fmt.println("      --theme NAME        ink | ember | moss | slate | rose | mono | dusk")
	fmt.println("      --mode MODE         ask | plan | review | edit")
	fmt.println("      --perms POLICY      ask | allow | yolo")
	fmt.println("      --sandbox MODE      off | soft | warn | strict | on")
	fmt.println("      --askpass            sudo/doas askpass helper (internal)")
	fmt.println("      --elevate-broker P   run privilege broker on path (internal)")
	fmt.println("      --no-elevate         deny elevated commands (NULLRAY_ELEVATE=deny)")
	fmt.println("  -w, --workspace PATH    workspace root for tools/sandbox")
	fmt.println("      --session NAME      resume or create named session")
	fmt.println("      --list-sessions     list saved sessions and exit")
	fmt.println("      --search-sessions Q search session names and text")
	fmt.println("      --delete-session N  delete a named session")
	fmt.println("      --export-session N  export session to --out DIR")
	fmt.println("      --import-session P  import session from path or dir")
	fmt.println("      --as NAME           name for --import-session or --install-skill")
	fmt.println("      --list-skills       list loaded skills and exit")
	fmt.println("      --install-skill P   copy skill .md or package into config skills")
	fmt.println("      --uninstall-skill N remove a skill from config skills")
	fmt.println("      --skills PATH       extra skill root(s), comma-separated (repeatable)")
	fmt.println("      --keys PRESET       default | neovim | emacs")
	fmt.println("      --message-file PATH prompt from file (print mode)")
	fmt.println("      --out PATH          write final reply to file (or export dir)")
	fmt.println("      --plan-out PATH     plan mode artifact path")
	fmt.println("      --plan-in PATH      load Done Contract and apply (print edit)")
	fmt.println("      --output-format F   text | json (print mode)")
	fmt.println("      --print-strict      exit 1 on incomplete plan/verify/living subagents")
	fmt.println("      --auto              autonomous edit (NULLRAY_AUTO=1, 80 steps)")
	fmt.println("      --usage             print token/cost summary (print mode)")
	fmt.println("      --timeout SEC       print-mode wall clock limit (default 600)")
	fmt.println("      --bare              skip home MCP and non-workspace skills")
	fmt.println("                          (NULLRAY_SKILLS / --skills still load)")
	fmt.println("      --fail-on-findings  exit 1 when review FINDINGS: N > 0")
	fmt.println("      --no-splash         skip startup splash")
	fmt.println("      --no-subagents      disable subagent task tool")
	fmt.println("      --splash            force startup splash")
	fmt.println("      --hide-sensitive    hide account and API key balances")
	fmt.println("      --list-models       list models for active provider and exit")
	fmt.println("      --completions SHELL print completion script and exit")
	fmt.println("      --man               print man page source and exit")
	fmt.println("")
	fmt.println("print mode defaults: ephemeral session, mode ask (edit when --plan-in).")
	fmt.println("edit under print needs --perms allow|yolo. Pipe stdin when not a TTY.")
	fmt.println("plan-in applies a Done Contract: empty prompt becomes Execute the approved plan.")
	fmt.println("")
	fmt.println("env file:  ~/.config/nullray/env")
	fmt.println("env vars:  NULLRAY_PROVIDER NULLRAY_MODEL NULLRAY_THEME NULLRAY_MODE NULLRAY_PERMS")
	fmt.println("           NULLRAY_SANDBOX NULLRAY_WORKSPACE NULLRAY_SESSION NULLRAY_EPHEMERAL")
	fmt.println("           NULLRAY_SPLASH NULLRAY_KEYS NULLRAY_STREAM OPENROUTER_API_KEY")
	fmt.println("           NULLRAY_HTTP_RETRIES NULLRAY_FALLBACK_MODELS NULLRAY_OPENROUTER_IGNORE")
	fmt.println("           NULLRAY_MCP_ALLOW_ANY NULLRAY_MCP_APPROVE_DRIFT NULLRAY_WORKSPACE_TRUST")
	fmt.println("           NULLRAY_HIDE_SENSITIVE NULLRAY_BARE NULLRAY_PRINT_TIMEOUT NULLRAY_OUT")
	fmt.println("           NULLRAY_PRINT_STRICT NULLRAY_PRINT_USAGE NULLRAY_USAGE NULLRAY_USAGE_PERSIST")
	fmt.println("           NULLRAY_PLAN_OUT NULLRAY_PLAN_IN NULLRAY_COLOR NULLRAY_ALT_SCREEN NULLRAY_MOUSE")
	fmt.println("           NULLRAY_DEBUG OPENAI_API_KEY OPENAI_BASE_URL OLLAMA_HOST")
	fmt.println("           LM_STUDIO_HOST LM_API_TOKEN")
	fmt.println("")
	fmt.println("completions: nullray --completions bash|zsh|fish|powershell|elvish|nushell")
	fmt.println("man page:    nullray --man | man -l -")
}

env_or :: proc(key, fallback: string) -> string {
	if v, ok := os.lookup_env(key, context.temp_allocator); ok {
		return v
	}
	return fallback
}
