// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
Serve client: ndjson JSON-RPC over the unix socket. Used by
--print --connect and attach. Notifications interleave with responses,
so client_wait takes a callback for them.
*/

package serve

import c "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"
import "nullray:constants"
import "nullray:mcp"

Client :: struct {
	fd:      posix.FD,
	mu:      sync.Mutex, // serialize writers
	next_id: int,
	carry:   [dynamic]u8,
	open:    bool,
}

client_connect :: proc(path: string) -> (cli: Client, err: string) {
	fd, cerr := sock_connect(path)
	if len(cerr) > 0 {
		return {}, cerr
	}
	cli.fd = fd
	cli.open = true
	return cli, ""
}

client_close :: proc(cli: ^Client) {
	if cli.open {
		_ = posix.shutdown(cli.fd, .RDWR)
		_ = posix.close(cli.fd)
		cli.open = false
	}
	delete(cli.carry)
}

// Build and send a request, returns its id.
client_send :: proc(cli: ^Client, method: string, params_json: string) -> int {
	sync.mutex_lock(&cli.mu)
	defer sync.mutex_unlock(&cli.mu)
	cli.next_id += 1
	id := cli.next_id
	payload := mcp.build_request(id, method, params_json, context.temp_allocator)
	line := strings.concatenate({payload, "\n"}, context.temp_allocator)
	client_write(cli, transmute([]u8)line)
	return id
}

@(private)
client_write :: proc(cli: ^Client, data: []u8) {
	total: uint = 0
	for total < len(data) {
		n := posix.send(cli.fd, raw_data(data[total:]), c.size_t(len(data) - total), {.NOSIGNAL})
		if n <= 0 {
			if posix.errno() == .EINTR {
				continue
			}
			cli.open = false
			return
		}
		total += uint(n)
	}
}

// Best-effort error reply to an inbound request we cannot answer.
client_reject :: proc(cli: ^Client, id_json: string, message: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	strings.write_string(&b, id_json)
	strings.write_string(&b, `,"error":{"code":-32601,"message":`)
	mcp.write_json_string(&b, message)
	strings.write_string(&b, `}}`)
	sync.mutex_lock(&cli.mu)
	defer sync.mutex_unlock(&cli.mu)
	line := strings.concatenate({strings.to_string(b), "\n"}, context.temp_allocator)
	client_write(cli, transmute([]u8)line)
}

// Read one ndjson line. Returned line is a heap clone, caller frees.
client_read_line :: proc(cli: ^Client, timeout_ms: int) -> (line: string, ok: bool) {
	for {
		for b, i in cli.carry {
			if b == '\n' {
				out := strings.clone(string(cli.carry[:i]))
				rest := len(cli.carry) - i - 1
				copy(cli.carry[:rest], cli.carry[i + 1:])
				resize(&cli.carry, rest)
				return out, true
			}
		}
		if timeout_ms >= 0 {
			pfd := posix.pollfd{fd = cli.fd, events = {.IN}}
			n := posix.poll(&pfd, 1, c.int(timeout_ms))
			if n <= 0 {
				if n < 0 && posix.errno() == .EINTR {
					continue
				}
				return "", false
			}
		}
		buf: [8192]u8
		for {
			n := posix.read(cli.fd, raw_data(buf[:]), c.size_t(uint(len(buf))))
			if n < 0 && posix.errno() == .EINTR {
				continue
			}
			if n <= 0 {
				return "", false
			}
			append(&cli.carry, ..buf[:n])
			break
		}
	}
}

Wait_Cb :: proc(obj: json.Object, user: rawptr)

// Read until the response for want_id lands. Notifications go to
// on_notify, inbound requests get a method-not-found reply. Returns the
// raw response line (allocator, caller frees) or an error string
// (allocator). raw is "" when err is set.
client_wait :: proc(
	cli: ^Client,
	want_id: int,
	on_notify: Wait_Cb = nil,
	user: rawptr = nil,
	timeout_sec: int = 0,
	allocator := context.allocator,
) -> (
	raw: string,
	err: string,
) {
	deadline := time.tick_now()
	limit := time.Duration(timeout_sec) * time.Second
	for {
		wait_ms := -1
		if timeout_sec > 0 {
			remain := limit - time.tick_since(deadline)
			if remain <= 0 {
				return "", strings.clone("timed out waiting for daemon", allocator)
			}
			wait_ms = int(time.duration_milliseconds(remain))
			if wait_ms > 1000 {
				wait_ms = 1000
			}
		}
		line, ok := client_read_line(cli, wait_ms)
		if !ok {
			if timeout_sec > 0 && time.tick_since(deadline) < limit {
				continue
			}
			return "", strings.clone("connection to daemon closed", allocator)
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
		_, has_method := jobj_str(obj, "method")
		id_v, has_id := obj["id"]
		if has_method {
			if has_id {
				// Inbound request (elicitation/create): not supported.
				client_reject(cli, fmt.tprintf("%v", id_v), "not supported")
			} else if on_notify != nil {
				on_notify(obj, user)
			}
		}
		matched := !has_method && has_id
		if matched {
			matched = false
			#partial switch iv in id_v {
			case json.Integer:
				matched = int(iv) == want_id
			case json.Float:
				matched = int(iv) == want_id
			}
		}
		free_all(context.temp_allocator)
		if !matched {
			delete(line)
			continue
		}
		// The caller re-parses raw to extract result fields.
		raw := strings.clone(line, allocator)
		delete(line)
		return raw, ""
	}
}

// Pull the error message out of a raw response line, or "" for success.
// Borrowed string is valid until the next temp reset.
response_error :: proc(raw: string, allocator := context.temp_allocator) -> string {
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return strings.clone("invalid daemon response", allocator)
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return strings.clone("invalid daemon response", allocator)
	}
	if eobj, ok := obj["error"].(json.Object); ok {
		msg, _ := jobj_str(eobj, "message")
		if len(msg) == 0 {
			msg = "daemon error"
		}
		return strings.clone(msg, allocator)
	}
	return ""
}

// Extract result.key as a heap-cloned string.
response_result_str :: proc(raw: string, key: string, allocator := context.allocator) -> string {
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return ""
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return ""
	}
	res, ok := obj["result"].(json.Object)
	if !ok {
		return ""
	}
	s, _ := jobj_str(res, key)
	return strings.clone(s, allocator)
}

// jobj_str mirror (acp helpers are package-private).
jobj_str :: proc(obj: json.Object, key: string) -> (string, bool) {
	v, ok := obj[key]
	if !ok {
		return "", false
	}
	s, is_s := v.(json.String)
	if !is_s {
		return "", false
	}
	return string(s), true
}

Print_Note_Ctx :: struct {
	session_id: string,
	text:       ^strings.Builder,
	last_nl:    ^bool,
}

// session/update handler for --print --connect: stream agent text to
// stdout and collect it for --out.
print_on_notify :: proc(obj: json.Object, user: rawptr) {
	ctx := cast(^Print_Note_Ctx)user
	params, ok := obj["params"].(json.Object)
	if !ok {
		return
	}
	sid, _ := jobj_str(params, "sessionId")
	if len(ctx.session_id) > 0 && sid != ctx.session_id {
		return
	}
	update, ok2 := params["update"].(json.Object)
	if !ok2 {
		return
	}
	kind, _ := jobj_str(update, "sessionUpdate")
	if kind != "agent_message_chunk" {
		return
	}
	content, ok3 := update["content"].(json.Object)
	if !ok3 {
		return
	}
	text, _ := jobj_str(content, "text")
	if len(text) == 0 {
		return
	}
	fmt.print(text)
	os.flush(os.stdout)
	strings.write_string(ctx.text, text)
	ctx.last_nl^ = strings.has_suffix(text, "\n")
}

run_print_via_serve :: proc(prompt: string, cwd: string, timeout_sec: int) -> int {
	path := sock_path(context.temp_allocator)
	cli: Client
	cerr: string
	cli, cerr = client_connect(path)
	if len(cerr) > 0 {
		fmt.eprintln("no nullray serve running (start with: nullray serve)")
		return 2
	}
	defer client_close(&cli)

	// initialize
	init_id := client_send(&cli, "initialize", `{"protocolVersion":1,"clientCapabilities":{}}`)
	_, ierr := client_wait(&cli, init_id)
	if len(ierr) > 0 {
		fmt.eprintln("nullray:", ierr)
		return 1
	}

	// session/new
	nb: strings.Builder
	strings.builder_init(&nb, context.temp_allocator)
	strings.write_string(&nb, `{"cwd":`)
	mcp.write_json_string(&nb, cwd)
	strings.write_byte(&nb, '}')
	new_id := client_send(&cli, "session/new", strings.to_string(nb))
	raw, nerr := client_wait(&cli, new_id)
	defer delete(raw)
	if len(nerr) > 0 {
		fmt.eprintln("nullray:", nerr)
		return 1
	}
	if emsg := response_error(raw); len(emsg) > 0 {
		fmt.eprintln("nullray:", emsg)
		return 1
	}
	session_id := response_result_str(raw, "sessionId")
	if len(session_id) == 0 {
		fmt.eprintln("nullray: daemon returned no sessionId")
		return 1
	}
	defer delete(session_id)

	// session/prompt
	pb: strings.Builder
	strings.builder_init(&pb, context.temp_allocator)
	strings.write_string(&pb, `{"sessionId":`)
	mcp.write_json_string(&pb, session_id)
	strings.write_string(&pb, `,"prompt":[{"type":"text","text":`)
	mcp.write_json_string(&pb, prompt)
	strings.write_string(&pb, `}]}`)
	prompt_id := client_send(&cli, "session/prompt", strings.to_string(pb))

	last_nl := true
	text: strings.Builder
	strings.builder_init(&text)
	defer strings.builder_destroy(&text)
	ctx := Print_Note_Ctx{session_id = session_id, text = &text, last_nl = &last_nl}
	_, perr := client_wait(&cli, prompt_id, print_on_notify, &ctx, timeout_sec)
	if len(perr) > 0 {
		fmt.eprintln("nullray:", perr)
		return 1
	}
	if !last_nl {
		fmt.println()
	}
	return 0
}
