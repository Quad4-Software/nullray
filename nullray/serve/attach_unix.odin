// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
nullray attach [SESSION]: minimal interactive client for a serve
daemon. Picks the newest session (or the named one), subscribes for
session/update notifications, and turns each stdin line into a
session/prompt. Ctrl-D or "exit" detaches, the session stays alive in
the daemon.
*/

package serve

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:mcp"

Attach_State :: struct {
	cli:        ^Client,
	session_id: string,
	mu:         sync.Mutex,
	waiters:    map[int]bool, // request ids the main loop is tracking
}

DIM :: "\x1b[2m"
RESET :: "\x1b[0m"

// Render one session/update notification for the attached session.
attach_render_update :: proc(params: json.Object, sid: string) {
	psid, _ := jobj_str(params, "sessionId")
	if psid != sid {
		return
	}
	update, ok := params["update"].(json.Object)
	if !ok {
		return
	}
	kind, _ := jobj_str(update, "sessionUpdate")
	switch kind {
	case "agent_message_chunk":
		if content, ok := update["content"].(json.Object); ok {
			if text, ok2 := jobj_str(content, "text"); ok2 {
				fmt.print(text)
				_ = os.flush(os.stdout)
			}
		}
	case "agent_thought_chunk":
		if content, ok := update["content"].(json.Object); ok {
			if text, ok2 := jobj_str(content, "text"); ok2 {
				fmt.printf("%s%s%s", DIM, text, RESET)
				_ = os.flush(os.stdout)
			}
		}
	case "tool_call":
		title, _ := jobj_str(update, "title")
		fmt.printf("%s\n[tool] %s%s\n", DIM, title, RESET)
	case "tool_call_update":
		status, _ := jobj_str(update, "status")
		call, _ := jobj_str(update, "toolCallId")
		fmt.printf("%s[tool %s] %s%s\n", DIM, call, status, RESET)
	case "current_mode_update":
		mode, _ := jobj_str(update, "currentModeId")
		fmt.printf("%s[mode] %s%s\n", DIM, mode, RESET)
	}
}

// Reader thread: print notifications, resolve waiter ids.
attach_reader_main :: proc(data: rawptr) {
	st := cast(^Attach_State)data
	for {
		line, ok := client_read_line(st.cli, -1)
		if !ok {
			fmt.eprintln("\nnullray: daemon connection closed")
			return
		}
		doc, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			delete(line)
			continue
		}
		obj, is_obj := doc.(json.Object)
		if !is_obj {
			delete(line)
			continue
		}
		method, has_method := jobj_str(obj, "method")
		id_v, has_id := obj["id"]
		if has_method {
			if has_id {
				client_reject(st.cli, fmt.tprintf("%v", id_v), "not supported")
			} else if method == "session/update" {
				if params, ok := obj["params"].(json.Object); ok {
					attach_render_update(params, st.session_id)
				}
			}
		} else if has_id {
			id := -1
			#partial switch iv in id_v {
			case json.Integer:
				id = int(iv)
			case json.Float:
				id = int(iv)
			}
			sync.mutex_lock(&st.mu)
			waited := st.waiters[id]
			delete_key(&st.waiters, id)
			sync.mutex_unlock(&st.mu)
			if waited {
				if eobj, ok := obj["error"].(json.Object); ok {
					msg, _ := jobj_str(eobj, "message")
					fmt.eprintf("\nnullray: %s\n", msg)
				}
				fmt.print("\n")
				_ = os.flush(os.stdout)
			}
		}
		delete(line)
		free_all(context.temp_allocator)
	}
}

// Newest session id from a session/list response line ("acp-N", max N).
attach_pick_session :: proc(list_raw: string) -> string {
	doc, perr := json.parse_string(list_raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return ""
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return ""
	}
	res, rok := obj["result"].(json.Object)
	if !rok {
		return ""
	}
	arr, aok := res["sessions"].(json.Array)
	if !aok {
		return ""
	}
	best := ""
	best_n := -1
	for item in arr {
		sobj, iok := item.(json.Object)
		if !iok {
			continue
		}
		sid, _ := jobj_str(sobj, "sessionId")
		n := -1
		if idx := strings.last_index(sid, "-"); idx >= 0 {
			parsed := 0
			valid := len(sid[idx + 1:]) > 0
			for ch in sid[idx + 1:] {
				if ch < '0' || ch > '9' {
					valid = false
					break
				}
				parsed = parsed * 10 + int(ch - '0')
			}
			if valid {
				n = parsed
			}
		}
			if n > best_n {
			best_n = n
			best = sid
		}
	}
	return best
}

attach_send_prompt :: proc(st: ^Attach_State, text: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionId":`)
	mcp.write_json_string(&b, st.session_id)
	strings.write_string(&b, `,"prompt":[{"type":"text","text":`)
	mcp.write_json_string(&b, text)
	strings.write_string(&b, `}]}`)
	id := client_send(st.cli, "session/prompt", strings.to_string(b))
	sync.mutex_lock(&st.mu)
	st.waiters[id] = true
	sync.mutex_unlock(&st.mu)
}

run_attach :: proc(target: string) -> int {
	path := sock_path(context.temp_allocator)
	cli, cerr := client_connect(path)
	if len(cerr) > 0 {
		fmt.eprintln("no nullray serve running (start with: nullray serve)")
		return 2
	}
	defer client_close(&cli)

	init_id := client_send(&cli, "initialize", `{"protocolVersion":1,"clientCapabilities":{}}`)
	_, ierr := client_wait(&cli, init_id)
	if len(ierr) > 0 {
		fmt.eprintln("nullray:", ierr)
		return 1
	}

	sid := strings.trim_space(target)
	if len(sid) == 0 {
		list_id := client_send(&cli, "session/list", "{}")
		raw, lerr := client_wait(&cli, list_id)
		if len(lerr) > 0 {
			fmt.eprintln("nullray:", lerr)
			return 1
		}
		sid = attach_pick_session(raw)
		delete(raw)
	}
	if len(sid) == 0 {
		// Owned copy: temp scratch can roll before session/new is sent.
		cwd, _ := os.get_working_directory(context.allocator)
		defer delete(cwd)
		nb: strings.Builder
		strings.builder_init(&nb, context.temp_allocator)
		strings.write_string(&nb, `{"cwd":`)
		mcp.write_json_string(&nb, cwd)
		strings.write_byte(&nb, '}')
		new_id := client_send(&cli, "session/new", strings.to_string(nb))
		raw, nerr := client_wait(&cli, new_id)
		if len(nerr) > 0 {
			fmt.eprintln("nullray:", nerr)
			return 1
		}
		sid = response_result_str(raw, "sessionId", context.temp_allocator)
		delete(raw)
	}
	if len(sid) == 0 {
		fmt.eprintln("nullray: no session to attach to")
		return 1
	}
	// sid borrows temp memory that client_wait resets, pin a heap copy.
	session_id := strings.clone(sid)
	defer delete(session_id)

	// Subscribe: failure means the named session does not exist.
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	strings.write_string(&sb, `{"sessionId":`)
	mcp.write_json_string(&sb, session_id)
	strings.write_byte(&sb, '}')
	sub_id := client_send(&cli, "session/subscribe", strings.to_string(sb))
	raw, serr := client_wait(&cli, sub_id)
	if len(serr) > 0 {
		fmt.eprintln("nullray:", serr)
		return 1
	}
	if emsg := response_error(raw); len(emsg) > 0 {
		fmt.eprintf("nullray: %s\n", emsg)
		delete(raw)
		return 1
	}
	delete(raw)

	st := Attach_State{cli = &cli, session_id = session_id, waiters = make(map[int]bool)}
	defer delete(st.waiters)
	reader := thread.create_and_start_with_data(&st, attach_reader_main, nil, .Normal, false)
	if reader == nil {
		fmt.eprintln("nullray: failed to start reader")
		return 1
	}
	// The reader is left running for the process lifetime, exiting is a
	// return to os.exit, so no join is needed.
	_ = reader

	fmt.printf("attached to %s (Ctrl-D or exit to detach)\n", session_id)
	buf: [4096]u8
	carry: [dynamic]u8
	defer delete(carry)
	for {
		n, _ := os.read(os.stdin, buf[:])
		if n <= 0 {
			break
		}
		for ch in buf[:n] {
			if ch == '\n' {
				line := strings.trim_space(string(carry[:]))
				clear(&carry)
				if line == "exit" || line == "quit" || line == "/exit" || line == "/quit" {
					return 0
				}
				if len(line) > 0 {
					attach_send_prompt(&st, line)
				}
				continue
			}
			append(&carry, ch)
		}
	}
	return 0
}
