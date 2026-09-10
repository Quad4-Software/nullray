// SPDX-License-Identifier: 0BSD
package main

import "core:fmt"
import "core:strings"
import "nullray:config"

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
		case "--review":
			cli.review_bot = true
		case "--staged":
			cli.review_staged = true
		case "--unstaged":
			cli.review_unstaged = true
		case "--include-untracked":
			cli.review_untracked = true
		case "--base":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--base needs a revision or branch"
				return cli
			}
			cli.review_base = v
		case "--review-scope":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--review-scope needs working|staged|unstaged|base"
				return cli
			}
			cli.review_scope = v
		case "--paths":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--paths needs a comma-separated list"
				return cli
			}
			cli.review_paths = v
		case "--doctor":
			cli.show_doctor = true
		case "--debug":
			cli.debug = true
		case "--list-models":
			cli.list_models = true
		case "--list-sessions":
			cli.list_sessions = true
		case "--inspect-session":
			cli.inspect_set = true
			if i + 1 < len(args) && !strings.has_prefix(args[i + 1], "-") {
				v, ok := take_value(args, &i)
				if ok {
					cli.inspect_session = v
				}
			}
		case "--follow":
			cli.inspect_follow = true
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
		case "--rename-session":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--rename-session needs a name"
				return cli
			}
			cli.rename_session = v
		case "--force":
			cli.rename_force = true
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
		case "--hunt":
			cli.hunt = "auto"
			if i + 1 < len(args) && !strings.has_prefix(args[i + 1], "-") {
				v, ok := take_value(args, &i)
				if ok {
					cli.hunt = v
				}
			}
		case "--perms":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--perms needs a value"
				return cli
			}
			cli.perms = v
		case "--gate":
			v, ok := take_value(args, &i)
			if !ok {
				cli.err = "--gate needs 0..3 or ask|allow|yolo"
				return cli
			}
			cli.gate = v
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
