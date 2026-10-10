// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Failed-call echo prevention tests: a failed call is described, never
echoed verbatim, and the tool_call_id pairing stays intact.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

@(private)
FD_MARKER :: "ZQXWVYKJ-MARKER-ZQXWVYKJ-MARKER-ZQXWVYKJ-MARKER-ZQXWVYKJ-MARKER"

@(private)
FD_ARGS :: `{"path":"/tmp/nullray-fd-nope/x.txt","token":"` + FD_MARKER + `"}`

@(private)
FD_Chat :: struct {
	tool_name: string,
	args:      string,
}

@(private)
fd_mock_chat :: proc(p: ^provider.Provider, req: provider.Chat_Request, allocator := context.allocator) -> provider.Chat_Response {
	st := cast(^FD_Chat)p.user_data
	calls := make([]provider.Tool_Call, 1, allocator)
	calls[0] = provider.Tool_Call{
		id = strings.clone("fd-call-1", allocator),
		name = strings.clone(st.tool_name, allocator),
		arguments = strings.clone(st.args, allocator),
	}
	return provider.Chat_Response{
		ok = true,
		tool_calls = calls,
		finish_reason = strings.clone("tool_calls", allocator),
	}
}

@(private)
fd_fail_tool_run :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	return "", strings.clone("read failed: ENOENT", allocator)
}

@(private)
fd_turn :: proc(reg: ^tools.Registry, max_steps: int) -> Run_Result {
	st := FD_Chat{tool_name = "fd_fail", args = FD_ARGS}
	prov := provider.Provider{id = "mock", chat = fd_mock_chat, user_data = &st}
	cfg := Config{
		enable_tools = true,
		stream = false,
		mode = .Edit,
		tools_registry = reg,
		max_steps = max_steps,
	}
	msgs := []provider.Message{{role = .User, content = "go"}}
	req := Run_Request{prov = &prov, messages = msgs, tools_enabled = true, model = "mock-model"}
	return run_turn(req, cfg)
}

@(private)
fd_registry :: proc() -> tools.Registry {
	r: tools.Registry
	r.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&r, tools.Tool{name = "fd_fail", kind = .Read, run = fd_fail_tool_run})
	return r
}

@(test)
test_failed_call_recorded_described_not_echoed :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_FAILURE_DESC)
	reg := fd_registry()
	res := fd_turn(&reg, 2)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	found_call := false
	found_result := false
	for m in res.messages {
		if m.role == .Assistant {
			for tc in m.tool_calls {
				if tc.id == "fd-call-1" {
					found_call = true
					// The recorded call keeps name and id but the raw
					// arguments are gone.
					testing.expect_value(t, tc.name, "fd_fail")
					testing.expect(t, !strings.contains(tc.arguments, FD_MARKER))
					testing.expect(t, !strings.contains(tc.arguments, "nullray-fd-nope"))
					testing.expect(t, strings.contains(tc.arguments, "_nullray_scrubbed"))
				}
			}
		}
		if m.role == .Tool && m.tool_call_id == "fd-call-1" {
			found_result = true
			// Pairing intact: same id, same name, flagged as an error.
			testing.expect_value(t, m.name, "fd_fail")
			testing.expect(t, m.is_error)
			// Described, not echoed.
			testing.expect(t, strings.contains(m.content, "tool fd_fail failed"))
			testing.expect(t, strings.contains(m.content, "read failed"))
			testing.expect(t, strings.contains(m.content, "path=/tmp/nullray-fd-nope/x.txt"))
			testing.expect(t, !strings.contains(m.content, FD_MARKER))
			testing.expect(t, !strings.contains(m.content, `{"path"`))
			testing.expect(t, strings.contains(m.content, "observed:"))
			testing.expect(t, strings.contains(m.content, "alternatives:"))
		}
	}
	testing.expect(t, found_call)
	testing.expect(t, found_result)
}

@(test)
test_failed_call_describe_disabled :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_FAILURE_DESC, "0")
	defer os.unset_env(constants.ENV_FAILURE_DESC)
	reg := fd_registry()
	res := fd_turn(&reg, 1)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	found_call := false
	found_result := false
	for m in res.messages {
		if m.role == .Assistant {
			for tc in m.tool_calls {
				if tc.id == "fd-call-1" {
					found_call = true
					// Flag off keeps the verbatim arguments.
					testing.expect(t, strings.contains(tc.arguments, FD_MARKER))
				}
			}
		}
		if m.role == .Tool && m.tool_call_id == "fd-call-1" {
			found_result = true
			// Flag off keeps the old status envelope recording.
			testing.expect(t, strings.contains(m.content, "status=error"))
			testing.expect(t, strings.contains(m.content, "read failed"))
		}
	}
	testing.expect(t, found_call)
	testing.expect(t, found_result)
}

@(test)
test_scrub_failed_call_args_surface :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		provider.destroy_messages(msgs[:])
		delete(msgs)
	}
	tcs := make([]provider.Tool_Call, 1)
	tcs[0] = provider.Tool_Call{
		id = strings.clone("c9"),
		name = strings.clone("fd_fail"),
		arguments = strings.clone(FD_ARGS),
	}
	append(&msgs, provider.Message{
		role = .Assistant,
		content = fmt_tcall(FD_ARGS),
		tool_calls = tcs,
	})
	c := provider.Tool_Call{id = "c9", name = "fd_fail", arguments = FD_ARGS}
	scrub_failed_call_args(&msgs, c, context.allocator)
	tc := msgs[0].tool_calls[0]
	testing.expect_value(t, tc.id, "c9")
	testing.expect_value(t, tc.name, "fd_fail")
	testing.expect(t, !strings.contains(tc.arguments, FD_MARKER))
	testing.expect(t, !strings.contains(msgs[0].content, FD_MARKER))
}

@(private)
fmt_tcall :: proc(args: string) -> string {
	return strings.concatenate({"CALL ", `{"name":"fd_fail","arguments":`, args, "}"}, context.allocator)
}
