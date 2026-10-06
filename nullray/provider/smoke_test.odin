// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

// Canned chat backend: records the request and replays a scripted response.
@(private)
Fake_Smoke :: struct {
	calls:             int,
	ok:                bool,
	err:               string,
	content:           string,
	tool_calls:        []Tool_Call,
	last_max_tokens:   int,
	last_msg_count:    int,
	last_temp_set:     bool,
	last_choice_auto:  bool,
	last_tools_echo:   bool,
	last_sys_has_tool: bool,
}

@(private)
smoke_fake_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
	f := cast(^Fake_Smoke)p.user_data
	f.calls += 1
	f.last_max_tokens = req.max_tokens
	f.last_msg_count = len(req.messages)
	f.last_temp_set = req.temperature_set
	f.last_choice_auto = req.tool_choice == "auto"
	f.last_tools_echo = strings.contains(req.tools_json, "echo_tool")
	f.last_sys_has_tool = len(req.messages) > 0 && strings.contains(req.messages[0].content, "echo_tool")
	res := Chat_Response{
		ok = f.ok,
		content = strings.clone(f.content, allocator),
		err = strings.clone(f.err, allocator),
	}
	if len(f.tool_calls) > 0 {
		res.tool_calls = make([]Tool_Call, len(f.tool_calls), allocator)
		for tc, i in f.tool_calls {
			res.tool_calls[i] = clone_tool_call(tc, allocator)
		}
	}
	return res
}

// Stack fake: no owned strings, so never provider_destroy it.
@(private)
smoke_fake_provider :: proc(f: ^Fake_Smoke, id := "ollama") -> Provider {
	return Provider{id = id, chat = smoke_fake_chat, user_data = f}
}

@(private)
save_smoke_env :: proc() -> (saved: string, had: bool) {
	if v, ok := os.lookup_env(constants.ENV_MODEL_SMOKE, context.temp_allocator); ok {
		return strings.clone(v), true
	}
	return "", false
}

@(private)
restore_smoke_env :: proc(saved: string, had: bool) {
	if had {
		os.set_env(constants.ENV_MODEL_SMOKE, saved)
	} else {
		os.unset_env(constants.ENV_MODEL_SMOKE)
	}
	delete(saved)
}

@test
test_smoke_tool_call_pass :: proc(t: ^testing.T) {
	f := Fake_Smoke{
		ok = true,
		tool_calls = []Tool_Call{{id = "c1", name = "echo_tool", arguments = `{"text":"ping"}`}},
	}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_tool_call(&p, "fake-model"), Smoke_Result.Pass)
	testing.expect_value(t, f.calls, 1)
	testing.expect_value(t, f.last_max_tokens, constants.MODEL_SMOKE_MAX_TOKENS)
	testing.expect(t, f.last_temp_set)
	testing.expect(t, f.last_choice_auto)
	testing.expect(t, f.last_tools_echo)
	testing.expect(t, f.last_sys_has_tool)
	testing.expect_value(t, f.last_msg_count, 2)
}

@test
test_smoke_tool_call_no_call :: proc(t: ^testing.T) {
	f := Fake_Smoke{ok = true, content = "pong"}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Fail_No_Call)
}

@test
test_smoke_tool_call_invalid :: proc(t: ^testing.T) {
	f := Fake_Smoke{
		ok = true,
		tool_calls = []Tool_Call{{name = "echo_tool", arguments = `{not json`}},
	}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Fail_Invalid)

	// A call to the wrong tool still failed the required task.
	f.tool_calls = []Tool_Call{{name = "other_tool", arguments = `{"text":"x"}`}}
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Fail_Invalid)

	// Parseable args missing the required text key are invalid too.
	f.tool_calls = []Tool_Call{{name = "echo_tool", arguments = `{"other":"x"}`}}
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Fail_Invalid)

	// A valid echo_tool call alongside junk passes.
	f.tool_calls = []Tool_Call{
		{name = "other_tool", arguments = `{"text":"x"}`},
		{name = "echo_tool", arguments = `{"text":"ping"}`},
	}
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Pass)
}

@test
test_smoke_tool_call_error :: proc(t: ^testing.T) {
	f := Fake_Smoke{ok = false, err = "boom"}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_tool_call(&p, "m"), Smoke_Result.Fail_Error)

	// Nothing callable is skipped rather than failed.
	idle := Provider{id = "ollama"}
	testing.expect_value(t, smoke_tool_call(&idle, "m"), Smoke_Result.Skipped)
	testing.expect_value(t, smoke_tool_call(&p, ""), Smoke_Result.Skipped)
	testing.expect_value(t, f.calls, 1)
}

@test
test_smoke_enabled_matrix :: proc(t: ^testing.T) {
	saved, had := save_smoke_env()
	defer restore_smoke_env(saved, had)

	f := Fake_Smoke{}
	p := smoke_fake_provider(&f, "ollama")

	os.unset_env(constants.ENV_MODEL_SMOKE)
	testing.expect(t, !smoke_enabled(&p))

	on_vals := []string{"1", "on", "true", "yes"}
	for v in on_vals {
		os.set_env(constants.ENV_MODEL_SMOKE, v)
		testing.expect(t, smoke_enabled(&p))
	}
	off_vals := []string{"0", "off", "no", "nope", ""}
	for v in off_vals {
		os.set_env(constants.ENV_MODEL_SMOKE, v)
		testing.expect(t, !smoke_enabled(&p))
	}

	// auto fires only for local/compat ids with unconfirmed tool support.
	os.set_env(constants.ENV_MODEL_SMOKE, "auto")
	auto_ids := []string{"ollama", "llamacpp", "lmstudio", "openai-compat"}
	for id in auto_ids {
		q := smoke_fake_provider(&f, id)
		testing.expect(t, smoke_enabled(&q))
	}
	cloud := smoke_fake_provider(&f, "openai")
	testing.expect(t, !smoke_enabled(&cloud))
	testing.expect(t, !smoke_enabled(nil))

	// Confirmed tool support skips the smoke under auto.
	known := smoke_fake_provider(&f, "ollama")
	known.caps.tools_known = true
	known.caps.supports_tools = true
	testing.expect(t, !smoke_enabled(&known))
}

@test
test_smoke_run_if_enabled_caches :: proc(t: ^testing.T) {
	saved, had := save_smoke_env()
	defer restore_smoke_env(saved, had)
	smoke_cache_reset()
	defer smoke_cache_reset()

	os.set_env(constants.ENV_MODEL_SMOKE, "1")
	f := Fake_Smoke{
		ok = true,
		tool_calls = []Tool_Call{{name = "echo_tool", arguments = `{"text":"ping"}`}},
	}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_run_if_enabled(&p, "cache-model"), Smoke_Result.Pass)
	testing.expect_value(t, smoke_run_if_enabled(&p, "cache-model"), Smoke_Result.Pass)
	testing.expect_value(t, f.calls, 1)

	r, ok := smoke_result("ollama", "cache-model")
	testing.expect(t, ok)
	testing.expect_value(t, r, Smoke_Result.Pass)
	// The same model id on another provider is a separate verdict: the
	// second provider runs its own probe instead of sharing the cache.
	p2 := smoke_fake_provider(&f, "lmstudio")
	_, cross := smoke_result("lmstudio", "cache-model")
	testing.expect(t, !cross)
	testing.expect_value(t, smoke_run_if_enabled(&p2, "cache-model"), Smoke_Result.Pass)
	testing.expect_value(t, f.calls, 2)
	_, seen := smoke_result("ollama", "never-run")
	testing.expect(t, !seen)
}

@test
test_smoke_run_if_enabled_skips_when_off :: proc(t: ^testing.T) {
	saved, had := save_smoke_env()
	defer restore_smoke_env(saved, had)
	smoke_cache_reset()
	defer smoke_cache_reset()

	os.unset_env(constants.ENV_MODEL_SMOKE)
	f := Fake_Smoke{ok = true}
	p := smoke_fake_provider(&f)
	testing.expect_value(t, smoke_run_if_enabled(&p, "off-model"), Smoke_Result.Skipped)
	testing.expect_value(t, f.calls, 0)
	_, seen := smoke_result("ollama", "off-model")
	testing.expect(t, !seen)
}

@test
test_smoke_label :: proc(t: ^testing.T) {
	testing.expect_value(t, smoke_label(Smoke_Result.Pass), "ok")
	testing.expect_value(t, smoke_label(Smoke_Result.Fail_No_Call), "no-call")
	testing.expect_value(t, smoke_label(Smoke_Result.Fail_Invalid), "invalid")
	testing.expect_value(t, smoke_label(Smoke_Result.Fail_Error), "error")
	testing.expect_value(t, smoke_label(Smoke_Result.Skipped), "skipped")
	testing.expect_value(t, smoke_label(Smoke_Result.Untested), "untested")
}
