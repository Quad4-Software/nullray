package main

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:app"
import "nullray:config"
import "nullray:constants"
import "nullray:http"
import "nullray:mcp"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:selftest"
import "nullray:tools"
import "nullray:ui"

Cli :: struct {
	ephemeral:   bool,
	self_test:   bool,
	list_models: bool,
	show_help:   bool,
	show_version: bool,
	show_man:    bool,
	completions: string,
	provider:    string,
	model:       string,
	theme:       string,
	mode:        string,
	perms:       string,
	sandbox:     string,
	workspace:   string,
	session:     string,
	err:         string,
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

	if cli.list_models {
		os.exit(run_list_models())
	}

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

	tools.tools_init()
	defer tools.tools_destroy()

	mcp.mcp_init()
	defer mcp.mcp_destroy()
	mcp.mcp_autoload()

	if !http.global_init() {
		fmt.eprintln("nullray: curl init failed")
		os.exit(1)
	}
	defer http.global_cleanup()

	color := env_or(constants.ENV_COLOR, "")
	theme := env_or(constants.ENV_THEME, "ink")

	loop: ui.Loop
	if !ui.loop_init(&loop, color, theme) {
		fmt.eprintln("nullray: terminal init failed (need a TTY)")
		fmt.eprintln("nullray: tip: run `nullray --self-test` for a headless smoke check")
		os.exit(1)
	}
	defer ui.loop_close(&loop)

	a: app.App
	app.app_init(&a, &loop)
	defer app.app_destroy(&a)

	ui.loop_run(&loop, app.app_draw, app.app_on_event, &a, app.app_is_dirty, app.app_on_tick)
}

parse_cli :: proc(args: []string) -> Cli {
	cli: Cli
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
		case "--list-models":
			cli.list_models = true
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
			cli.err = fmt.aprintf("unexpected argument: %s", arg)
			return cli
		}
		i += 1
	}
	return cli
}

take_value :: proc(args: []string, i: ^int) -> (string, bool) {
	if i^ + 1 >= len(args) {
		return "", false
	}
	i^ += 1
	return args[i^], true
}

apply_cli_env :: proc(cli: ^Cli) {
	if cli.ephemeral {
		os.set_env(constants.ENV_EPHEMERAL, "1")
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
	if len(cli.workspace) > 0 {
		os.set_env(constants.ENV_WORKSPACE, cli.workspace)
	}
	if len(cli.session) > 0 {
		os.set_env(constants.ENV_SESSION, cli.session)
	}
}

run_list_models :: proc() -> int {
	if !http.global_init() {
		fmt.eprintln("nullray: curl init failed")
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

print_version :: proc() {
	fmt.printf("%s %s (built %s %s)\n", constants.APP_NAME, constants.VERSION, constants.BUILD_DATE, constants.BUILD_TIME)
}

print_help :: proc() {
	print_version()
	fmt.println("usage: nullray [options]")
	fmt.println("")
	fmt.println("options:")
	fmt.println("  -h, --help              show this help")
	fmt.println("  -V, --version           show version and build stamp")
	fmt.println("  -e, --ephemeral         do not load or save session transcripts")
	fmt.println("  -t, --self-test         headless smoke (tools, mcp, draw, shell deny)")
	fmt.println("  -p, --provider ID       ollama | lmstudio | openai | openai-compat |")
	fmt.println("                          openrouter | opencode | opencode-go")
	fmt.println("  -m, --model NAME        override default model")
	fmt.println("      --theme NAME        ink | ember | moss | slate | rose | mono | dusk")
	fmt.println("      --mode MODE         ask | plan | edit")
	fmt.println("      --perms POLICY      ask | allow | yolo")
	fmt.println("      --sandbox MODE      on | off | landlock | seccomp | ...")
	fmt.println("  -w, --workspace PATH    workspace root for tools/sandbox")
	fmt.println("      --session NAME      resume or create named session")
	fmt.println("      --list-models       list models for active provider and exit")
	fmt.println("      --completions SHELL print completion script and exit")
	fmt.println("      --man               print man page source and exit")
	fmt.println("")
	fmt.println("env file:  ~/.config/nullray/env")
	fmt.println("env vars:  NULLRAY_PROVIDER NULLRAY_MODEL NULLRAY_THEME NULLRAY_MODE NULLRAY_PERMS")
	fmt.println("           NULLRAY_SANDBOX NULLRAY_WORKSPACE NULLRAY_SESSION NULLRAY_EPHEMERAL")
	fmt.println("           NULLRAY_STREAM OPENROUTER_API_KEY OPENAI_API_KEY OPENAI_BASE_URL")
	fmt.println("           OLLAMA_HOST LM_STUDIO_HOST LM_API_TOKEN")
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
