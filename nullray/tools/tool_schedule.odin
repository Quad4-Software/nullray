// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Scheduled-prompt tools. schedule_prompt registers one-shot, interval, or
cron jobs that later wake the session as a user turn, schedule_list and
schedule_cancel inspect and drop them. State lives under .nullray so the
kind is Read, matching the board tools.
*/

package tools

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:schedule"
import "nullray:todo"

SCHEDULE_UNAVAILABLE :: "scheduler unavailable (NULLRAY_SCHEDULE=0)"

register_schedule_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "schedule_prompt",
		description = "Schedule a prompt to run later: at|every accepts durations like 10m/1h30m/7d, cron takes 5 fields. once=true runs a single time, durable=true survives restarts",
		schema_json = `{"type":"object","properties":{"prompt":{"type":"string"},"at":{"type":"string","description":"delay like 10m or wall clock HH:MM"},"every":{"type":"string","description":"interval like 30m, 1h, 90s"},"cron":{"type":"string","description":"5-field cron 'min hour dom mon dow'"},"once":{"type":"string","description":"true for a single run"},"durable":{"type":"string","description":"persist across restarts"},"max_runs":{"type":"string"},"expires_in":{"type":"string","description":"lifetime like 7d"}},"required":["prompt"]}`,
		kind = .Read,
		run = tool_schedule_prompt,
	})
	registry_register(r, Tool{
		name = "schedule_list",
		description = "List scheduled jobs with id, spec, next fire, and run count",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_schedule_list,
	})
	registry_register(r, Tool{
		name = "schedule_cancel",
		description = "Cancel a scheduled job by id, or all jobs with id=all",
		schema_json = `{"type":"object","properties":{"id":{"type":"string","description":"job id or 'all'"}},"required":["id"]}`,
		kind = .Read,
		run = tool_schedule_cancel,
	})
}

@(private)
schedule_tool_enabled :: proc(allocator := context.allocator) -> (ok: bool, err: string) {
	if !schedule.schedule_enabled() {
		return false, strings.clone(SCHEDULE_UNAVAILABLE, allocator)
	}
	return true, ""
}

tool_schedule_prompt :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if ok, e := schedule_tool_enabled(allocator); !ok {
		return "", e
	}
	prompt, perr := json_arg_string(args_json, "prompt", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(prompt)
	if len(strings.trim_space(prompt)) == 0 {
		return "", strings.clone("prompt required", allocator)
	}
	at, _ := json_arg_string_optional(args_json, "at", "", allocator)
	defer delete(at)
	every, _ := json_arg_string_optional(args_json, "every", "", allocator)
	defer delete(every)
	cron, _ := json_arg_string_optional(args_json, "cron", "", allocator)
	defer delete(cron)
	once, _ := json_arg_bool_string(args_json, "once", false)
	durable, _ := json_arg_bool_string(args_json, "durable", false)
	max_runs, _ := json_arg_int_optional(args_json, "max_runs", 0, allocator)
	expires_in, _ := json_arg_string_optional(args_json, "expires_in", "", allocator)
	defer delete(expires_in)

	spec := ""
	one_shot := once
	n_spec := 0
	if len(strings.trim_space(at)) > 0 {
		n_spec += 1
		a := strings.trim_space(at)
		if _, ok := schedule.dur_parse(a); ok {
			spec = fmt.tprintf("in %s", a)
			one_shot = true
		} else {
			spec = fmt.tprintf("at %s", a)
			one_shot = true
		}
	}
	if len(strings.trim_space(every)) > 0 {
		n_spec += 1
		spec = fmt.tprintf("every %s", strings.trim_space(every))
	}
	if len(strings.trim_space(cron)) > 0 {
		n_spec += 1
		spec = strings.trim_space(cron)
	}
	if n_spec == 0 {
		return "", strings.clone("one of at|every|cron is required", allocator)
	}
	if n_spec > 1 {
		return "", strings.clone("use only one of at|every|cron", allocator)
	}
	expires_sec: i64 = 0
	if len(strings.trim_space(expires_in)) > 0 {
		d, d_ok := schedule.dur_parse(strings.trim_space(expires_in))
		if !d_ok {
			return "", fmt.aprintf("bad expires_in duration: %s", expires_in, allocator = allocator)
		}
		expires_sec = d
	}
	now := schedule.unix_now()
	// Scope the job to the session running this turn so scoped wakeup
	// sinks (the serve daemon) can route the wakeup back to it.
	id, aerr := schedule.job_add(
		prompt,
		spec,
		todo.current_session(),
		durable,
		one_shot,
		max_runs,
		expires_sec,
		.Prompt,
		now,
	)
	if len(aerr) > 0 {
		defer delete(aerr)
		return "", strings.clone(aerr, allocator)
	}
	in_sec, _ := schedule.job_next_fire_in(id, now)
	return fmt.aprintf(
		"scheduled job %d (%s), next fire in %s",
		id,
		spec,
		schedule.fmt_delta(in_sec, context.temp_allocator),
		allocator = allocator,
	), ""
}

tool_schedule_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	if ok, e := schedule_tool_enabled(allocator); !ok {
		return "", e
	}
	return schedule.job_list_text(schedule.unix_now(), allocator), ""
}

tool_schedule_cancel :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if ok, e := schedule_tool_enabled(allocator); !ok {
		return "", e
	}
	id, ierr := json_arg_string(args_json, "id", allocator)
	if ierr != "" {
		return "", ierr
	}
	defer delete(id)
	trimmed := strings.trim_space(id)
	if trimmed == "all" {
		n := schedule.job_cancel_all()
		return fmt.aprintf("cancelled %d job(s)", n, allocator = allocator), ""
	}
	n, n_ok := strconv.parse_int(trimmed)
	if !n_ok {
		return "", fmt.aprintf("bad job id: %s", trimmed, allocator = allocator)
	}
	if !schedule.job_cancel(n) {
		return "", fmt.aprintf("no job %d", n, allocator = allocator)
	}
	return fmt.aprintf("cancelled job %d", n, allocator = allocator), ""
}
