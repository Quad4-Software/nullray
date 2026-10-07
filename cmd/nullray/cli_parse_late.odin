// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package main

import "core:fmt"
import "core:strings"

parse_cli_late :: proc(cli: ^Cli, args: []string, i: ^int, arg: string, prompt_parts: ^[dynamic]string) -> (handled: bool, done: bool) {
	switch arg {
	case "--message-file":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--message-file needs a path"
			return true, true
		}
		cli.message_file = v
	case "--image", "--audio", "--video", "--media":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = fmt.aprintf("%s needs a path", arg)
			return true, true
		}
		kind := ""
		if arg != "--media" {
			kind = arg[2:]
		}
		append(&cli.media_args, Media_Arg{path = v, kind = kind})
	case "--out":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--out needs a path"
			return true, true
		}
		cli.out_path = v
	case "--plan-out":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--plan-out needs a path"
			return true, true
		}
		cli.plan_out = v
	case "--plan-in":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--plan-in needs a path"
			return true, true
		}
		cli.plan_in = v
	case "--output-format":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--output-format needs text|json"
			return true, true
		}
		lv := strings.to_lower(v, context.temp_allocator)
		if lv != "text" && lv != "json" {
			cli.err = "--output-format needs text|json"
			return true, true
		}
		cli.output_format = lv
	case "--timeout":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--timeout needs seconds"
			return true, true
		}
		n, nok := parse_cli_int(v)
		if !nok || n <= 0 {
			cli.err = "--timeout needs a positive integer (seconds)"
			return true, true
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
	case "--samples":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--samples needs N"
			return true, true
		}
		n, nok := parse_cli_int(v)
		if !nok || n < 1 {
			cli.err = "--samples needs a positive integer"
			return true, true
		}
		cli.samples = n
	case "--architect":
		cli.architect = true
	case "--completions":
		v, ok := take_value(args, i)
		if !ok {
			cli.err = "--completions needs a shell name"
			return true, true
		}
		cli.completions = v
	}
	return false, false
}
