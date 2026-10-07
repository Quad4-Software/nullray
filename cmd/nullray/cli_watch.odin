// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
nullray watch: manage standing watches from the CLI. Watches are durable
scheduled jobs, so add/rm work offline against .nullray/scheduled_tasks.json
and .nullray/watch/<id>/, and a running daemon picks up store changes on
its next tick. When a daemon is live, add also opens a session so the
first wakeup has somewhere to land.
*/

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:mcp"
import "nullray:schedule"
import "nullray:serve"

watch_usage :: proc() {
	fmt.println("usage: nullray watch <subcommand>")
	fmt.println("  watch add <every|in|at|cron> <instruction> [--max-runs N] [--max-tokens N] [--expires DUR]")
	fmt.println("       spec forms: 2h | \"every 2h\" | \"at 09:00\" | \"0 8 * * 1\"")
	fmt.println("  watch list                 list watches with next fire and expiry")
	fmt.println("  watch rm <id>              remove a watch and its state")
	fmt.println("  watch show <id>            state plus digest tail")
	fmt.println("  watch status               digest tail summary for all watches")
}

run_watch :: proc(args: []string) -> int {
	if !schedule.schedule_enabled() {
		fmt.eprintln("nullray watch: scheduler is off (NULLRAY_SCHEDULE=0)")
		return 1
	}
	if len(args) == 0 {
		watch_usage()
		return 0
	}
	schedule.schedule_init()
	switch args[0] {
	case "add":
		return watch_cmd_add(args[1:])
	case "list", "ls", "status":
		text := schedule.watch_list_text(schedule.unix_now(), context.temp_allocator)
		fmt.print(text)
		return 0
	case "rm", "remove", "cancel", "del", "delete":
		return watch_cmd_rm(args[1:])
	case "show":
		return watch_cmd_show(args[1:])
	case "help", "-h", "--help":
		watch_usage()
		return 0
	case:
		fmt.eprintf("nullray watch: unknown subcommand %s\n", args[0])
		watch_usage()
		return 2
	}
}

watch_cmd_add :: proc(args: []string) -> int {
	max_runs := 0
	max_tokens: i64 = 0
	expires_sec: i64 = 0
	pos := make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(args) {
		a := args[i]
		switch a {
		case "--max-runs":
			v, ok := take_value(args, &i)
			if !ok {
				fmt.eprintln("nullray watch: --max-runs needs N")
				return 2
			}
			n, nok := strconv.parse_int(v)
			if !nok || n < 0 {
				fmt.eprintln("nullray watch: --max-runs needs a non-negative integer")
				return 2
			}
			max_runs = n
		case "--max-tokens":
			v, ok := take_value(args, &i)
			if !ok {
				fmt.eprintln("nullray watch: --max-tokens needs N")
				return 2
			}
			n, nok := strconv.parse_i64(v)
			if !nok || n < 0 {
				fmt.eprintln("nullray watch: --max-tokens needs a non-negative integer")
				return 2
			}
			max_tokens = n
		case "--expires":
			v, ok := take_value(args, &i)
			if !ok {
				fmt.eprintln("nullray watch: --expires needs a duration like 7d")
				return 2
			}
			d, dok := schedule.dur_parse(v)
			if !dok {
				fmt.eprintf("nullray watch: bad --expires duration %s\n", v)
				return 2
			}
			expires_sec = d
		case:
			if strings.has_prefix(a, "-") {
				fmt.eprintf("nullray watch: unknown flag %s\n", a)
				return 2
			}
			append(&pos, a)
		}
		i += 1
	}
	// spec and prompt must be heap: the daemon handshake below runs
	// free_all on the temp arena (client_wait), which would corrupt them.
	spec, rest, sperr := schedule.watch_spec_parse(pos[:], context.allocator)
	if len(sperr) > 0 {
		defer delete(sperr)
		fmt.eprintln("nullray watch:", sperr)
		return 2
	}
	defer delete(spec)
	if len(rest) == 0 {
		fmt.eprintln("nullray watch: add needs an instruction after the spec")
		return 2
	}
	prompt := strings.join(rest, " ", context.allocator)
	defer delete(prompt)
	// A live daemon gets a dedicated session so wakeups have a target
	// even before any client has prompted. Returned on temp, no further
	// client_wait calls can free_all it away.
	scope := watch_daemon_scope(context.temp_allocator)
	now := schedule.unix_now()
	id, aerr := schedule.watch_add(prompt, spec, scope, max_runs, max_tokens, expires_sec, now)
	if len(aerr) > 0 {
		defer delete(aerr)
		fmt.eprintln("nullray watch:", aerr)
		return 1
	}
	in_sec, _ := schedule.job_next_fire_in(id, now)
	fmt.printf(
		"watch %d added (%s), next fire in %s",
		id, spec, schedule.fmt_delta(in_sec, context.temp_allocator),
	)
	if len(scope) > 0 {
		fmt.printf(", daemon session %s", scope)
	}
	fmt.println()
	if len(scope) == 0 {
		fmt.println("note: start `nullray serve` or the TUI for wakeups to run")
	}
	if expires_sec <= 0 && schedule.spec_recurring(spec) {
		fmt.printf("note: recurring watches auto-expire after %d days\n", constants.SCHEDULE_RECURRING_EXPIRE_DAYS)
	}
	return 0
}

watch_cmd_rm :: proc(args: []string) -> int {
	if len(args) < 1 {
		fmt.eprintln("usage: nullray watch rm <id>")
		return 2
	}
	id, ok := strconv.parse_int(strings.trim_space(args[0]))
	if !ok || id <= 0 {
		fmt.eprintf("nullray watch: bad id %s\n", args[0])
		return 2
	}
	if !schedule.watch_rm(id) {
		fmt.eprintf("nullray watch: no watch %d\n", id)
		return 1
	}
	fmt.printf("removed watch %d\n", id)
	return 0
}

watch_cmd_show :: proc(args: []string) -> int {
	if len(args) < 1 {
		fmt.eprintln("usage: nullray watch show <id>")
		return 2
	}
	id, ok := strconv.parse_int(strings.trim_space(args[0]))
	if !ok || id <= 0 {
		fmt.eprintf("nullray watch: bad id %s\n", args[0])
		return 2
	}
	text := schedule.watch_show_text(id, context.temp_allocator)
	fmt.print(text)
	return 0
}

/*
Create a session on a live daemon so scoped wakeups have a target.
Returns "" when no daemon is listening. Unix only.
*/
watch_daemon_scope :: proc(allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		return ""
	} else {
		path := serve.sock_path(context.temp_allocator)
		if len(path) == 0 || !serve.sock_live(path) {
			return ""
		}
		cli, cerr := serve.client_connect(path)
		if len(cerr) > 0 {
			return ""
		}
		defer serve.client_close(&cli)
		init_id := serve.client_send(&cli, "initialize", `{"protocolVersion":1,"clientCapabilities":{}}`)
		raw, werr := serve.client_wait(&cli, init_id)
		if len(werr) > 0 {
			delete(werr)
			return ""
		}
		delete(raw)
		cwd, cwd_err := os.get_working_directory(context.temp_allocator)
		if cwd_err != nil {
			return ""
		}
		nb: strings.Builder
		strings.builder_init(&nb, context.temp_allocator)
		strings.write_string(&nb, `{"cwd":`)
		mcp.write_json_string(&nb, cwd)
		strings.write_byte(&nb, '}')
		new_id := serve.client_send(&cli, "session/new", strings.to_string(nb))
		raw2, werr2 := serve.client_wait(&cli, new_id)
		if len(werr2) > 0 {
			delete(werr2)
			return ""
		}
		defer delete(raw2)
		if emsg := serve.response_error(raw2); len(emsg) > 0 {
			delete(emsg)
			return ""
		}
		return serve.response_result_str(raw2, "sessionId", allocator)
	}
}
