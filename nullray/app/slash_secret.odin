// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/secret: list, add, forget agent vault secrets (values never printed).
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"
import "nullray:ask"
import "nullray:session"

slash_cmd_secret :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "list" || low == "ls" {
		names := ask.secret_names(context.temp_allocator)
		if len(names) == 0 {
			session.session_set_status(a.session, "secrets: (none) · /secret set NAME | ask NAME | forget NAME")
			return
		}
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, "secrets (names only):")
		for n in names {
			strings.write_string(&b, " ")
			strings.write_string(&b, n)
		}
		session.session_push_assistant(a.session, strings.to_string(b))
		session.session_set_status(a.session, fmt.tprintf("%d secrets vaulted", len(names)))
		return
	}
	if low == "clear" {
		ask.secrets_clear()
		session.session_set_status(a.session, "secrets cleared")
		return
	}
	if strings.has_prefix(low, "forget ") || strings.has_prefix(low, "rm ") || strings.has_prefix(low, "delete ") {
		name := strings.trim_space(rest[strings.index(rest, " ") + 1:])
		if len(name) == 0 {
			session.session_set_status(a.session, "usage: /secret forget NAME")
			return
		}
		if ask.secret_forget(name) {
			session.session_set_status(a.session, fmt.tprintf("forgot secret %s", name))
		} else {
			session.session_set_status(a.session, fmt.tprintf("no secret %s", name))
		}
		return
	}
	if strings.has_prefix(low, "has ") || strings.has_prefix(low, "check ") {
		name := strings.trim_space(rest[strings.index(rest, " ") + 1:])
		if ask.secret_has(name) {
			session.session_set_status(a.session, fmt.tprintf("secret %s is set", name))
		} else {
			session.session_set_status(a.session, fmt.tprintf("secret %s is missing", name))
		}
		return
	}
	if strings.has_prefix(low, "ask ") || low == "ask" {
		name := ""
		if strings.has_prefix(low, "ask ") {
			name = strings.trim_space(rest[4:])
		}
		if len(name) == 0 {
			session.session_set_status(a.session, "usage: /secret ask NAME")
			return
		}
		app_secret_ask_async(a, name)
		return
	}
	if strings.has_prefix(low, "set ") || strings.has_prefix(low, "add ") || strings.has_prefix(low, "put ") {
		body := strings.trim_space(rest[strings.index(rest, " ") + 1:])
		name, value := secret_parse_set_args(body)
		if len(name) == 0 {
			session.session_set_status(a.session, "usage: /secret set NAME | NAME=VALUE")
			return
		}
		if len(value) == 0 {
			app_secret_ask_async(a, name)
			return
		}
		app_secret_store(name, value)
		session.session_set_status(a.session, fmt.tprintf("secret %s stored (value hidden)", name))
		app_mark_dirty(a)
		return
	}
	if strings.contains(rest, " ") || strings.contains(rest, "=") {
		session.session_set_status(a.session, "usage: /secret list|set|ask|forget|has|clear")
		return
	}
	app_secret_ask_async(a, rest)
}

app_secret_store :: proc(name, value: string) {
	ask.secret_put(name, value)
	_ = ask.secret_bind_env(name)
	os.set_env(name, value)
}

@(private)
secret_parse_set_args :: proc(body: string) -> (name, value: string) {
	b := strings.trim_space(body)
	if len(b) == 0 {
		return "", ""
	}
	if eq := strings.index_byte(b, '='); eq > 0 {
		return strings.trim_space(b[:eq]), strings.trim_space(b[eq + 1:])
	}
	if sp := strings.index_byte(b, ' '); sp > 0 {
		return strings.trim_space(b[:sp]), strings.trim_space(b[sp + 1:])
	}
	return b, ""
}

Secret_Ask_Box :: struct {
	name: string,
}

app_secret_ask_async :: proc(a: ^App, name: string) {
	_ = a
	box := new(Secret_Ask_Box)
	box.name = strings.clone(name)
	session.session_set_status(a.session, fmt.tprintf("enter secret for %s…", name))
	app_mark_dirty(a)
	thread.create_and_start_with_data(box, secret_ask_worker)
}

@(private)
secret_ask_worker :: proc(data: rawptr) {
	box := cast(^Secret_Ask_Box)data
	defer {
		delete(box.name)
		free(box)
	}
	prompt := fmt.aprintf("Enter secret for %s:", box.name)
	defer delete(prompt)
	answer, ok, cancelled := ask.request(.Secret, prompt, nil, true, 600)
	if cancelled || !ok {
		delete(answer)
		return
	}
	if len(strings.trim_space(answer)) == 0 {
		delete(answer)
		return
	}
	app_secret_store(box.name, answer)
	delete(answer)
}
