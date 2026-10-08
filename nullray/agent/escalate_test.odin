// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
SWE-Protege escalation tests: env target parsing, verdict to escalate
mapping, cap and same-signature dedup, backend pick, and end-to-end
one-shot escalation plus silent degrade through run_turn.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

@(test)
test_escalate_target_from_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_ESCALATE_MODEL)
	_, ok := escalate_target_from_env()
	testing.expect(t, !ok)
	os.set_env(constants.ENV_ESCALATE_MODEL, "openrouter/anthropic/claude-x")
	defer os.unset_env(constants.ENV_ESCALATE_MODEL)
	target, ok2 := escalate_target_from_env(context.allocator)
	defer delete(target.model)
	testing.expect(t, ok2)
	testing.expect_value(t, target.provider_id, "openrouter")
	testing.expect_value(t, target.model, "anthropic/claude-x")
}

@(test)
test_escalate_target_model_only_and_unknown_head :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_ESCALATE_MODEL, "qwen3-32b")
	defer os.unset_env(constants.ENV_ESCALATE_MODEL)
	target, ok := escalate_target_from_env(context.allocator)
	defer delete(target.model)
	testing.expect(t, ok)
	testing.expect_value(t, target.provider_id, "")
	testing.expect_value(t, target.model, "qwen3-32b")
	// A head that is not a known provider stays a model name on base.
	os.set_env(constants.ENV_ESCALATE_MODEL, "nosuchprovider/m-x")
	target2, ok2 := escalate_target_from_env(context.allocator)
	defer delete(target2.model)
	testing.expect(t, ok2)
	testing.expect_value(t, target2.provider_id, "")
	testing.expect_value(t, target2.model, "nosuchprovider/m-x")
}

@(test)
test_escalate_max_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_ESCALATE_MAX)
	testing.expect_value(t, escalate_max_from_env(), constants.ESCALATE_MAX_DEFAULT)
	os.set_env(constants.ENV_ESCALATE_MAX, "1")
	defer os.unset_env(constants.ENV_ESCALATE_MAX)
	testing.expect_value(t, escalate_max_from_env(), 1)
	os.set_env(constants.ENV_ESCALATE_MAX, "99")
	testing.expect_value(t, escalate_max_from_env(), constants.ESCALATE_MAX_CAP)
	os.set_env(constants.ENV_ESCALATE_MAX, "0")
	testing.expect_value(t, escalate_max_from_env(), 0)
}

@(test)
test_escalate_should_mapping_cap_dedup :: proc(t: ^testing.T) {
	st := Escalate_State{armed = true, max = 2}
	// No stall, no escalation.
	testing.expect(t, !escalate_should(&st, false, 111))
	// Stall schedules exactly once.
	testing.expect(t, escalate_should(&st, true, 111))
	testing.expect(t, st.pending)
	testing.expect_value(t, st.used, 1)
	// Pending blocks a second schedule.
	testing.expect(t, !escalate_should(&st, true, 222))
	st.pending = false
	// Same signature never re-escalates.
	testing.expect(t, !escalate_should(&st, true, 111))
	// A different stall signature can, until the cap.
	testing.expect(t, escalate_should(&st, true, 222))
	st.pending = false
	testing.expect(t, !escalate_should(&st, true, 333))
	testing.expect_value(t, st.used, 2)
	// Disarmed never schedules.
	off := Escalate_State{armed = false, max = 2}
	testing.expect(t, !escalate_should(&off, true, 111))
}

@(test)
test_escalate_pick_same_provider_model :: proc(t: ^testing.T) {
	base := provider.Provider{id = "mock", default_model = "base-model"}
	alt: provider.Provider
	p, m, ok := escalate_pick(Escalate_Target{model = "strong-model"}, &base, "base-model", &alt)
	testing.expect(t, ok)
	testing.expect(t, p == &base)
	testing.expect_value(t, m, "strong-model")
	// Same model on the same provider is not an escalation.
	_, _, ok2 := escalate_pick(Escalate_Target{model = "base-model"}, &base, "base-model", &alt)
	testing.expect(t, !ok2)
	// Unknown provider id declines so the caller degrades to base.
	_, _, ok3 := escalate_pick(Escalate_Target{provider_id = "nosuchprov"}, &base, "base-model", &alt)
	testing.expect(t, !ok3)
}

// -- End-to-end through run_turn ----------------------------------------

@(private)
Esc_Mock :: struct {
	calls:     int,
	fail:      bool,
	done_text: string,
}

@(private)
esc_mock_chat :: proc(p: ^provider.Provider, req: provider.Chat_Request, allocator := context.allocator) -> provider.Chat_Response {
	st := cast(^Esc_Mock)p.user_data
	st.calls += 1
	if st.fail {
		return provider.Chat_Response{ok = false, err = strings.clone("esc backend down", allocator)}
	}
	return provider.Chat_Response{
		ok = true,
		content = strings.clone(st.done_text, allocator),
		finish_reason = strings.clone("stop", allocator),
	}
}

@(private)
make_esc_provider :: proc(st: ^Esc_Mock) -> provider.Provider {
	// Owned strings so provider_destroy is safe on the fake.
	return provider.Provider{
		id = "escmock",
		name = "escmock",
		base_url = strings.clone("mock://esc"),
		api_key = strings.clone("k"),
		default_model = strings.clone("strong-model"),
		chat = esc_mock_chat,
		user_data = st,
	}
}

@(private)
g_test_esc_mock: ^Esc_Mock

@(private)
test_esc_make :: proc(id: string) -> (provider.Provider, bool) {
	if id == "escmock" && g_test_esc_mock != nil {
		return make_esc_provider(g_test_esc_mock), true
	}
	return provider.Provider{}, false
}

@(private)
esc_turn :: proc(t: ^testing.T, esc_st: ^Esc_Mock, reg: ^tools.Registry, max_steps: int) -> Run_Result {
	_ = t
	os.set_env(constants.ENV_ESCALATE_MODEL, "escmock/strong-model")
	st := Mock_Chat{tool_name = "fake_tool"}
	prov := provider.Provider{id = "mock", chat = mock_chat, user_data = &st}
	cfg := Config{
		enable_tools = true,
		stream = false,
		mode = .Edit,
		tools_registry = reg,
		max_steps = max_steps,
	}
	msgs := []provider.Message{{role = .User, content = "go"}}
	prev_make := g_escalate_make
	g_escalate_make = test_esc_make
	g_test_esc_mock = esc_st
	defer {
		g_escalate_make = prev_make
		g_test_esc_mock = nil
		os.unset_env(constants.ENV_ESCALATE_MODEL)
	}
	req := Run_Request{prov = &prov, messages = msgs, tools_enabled = true, model = "mock-model"}
	return run_turn(req, cfg)
}

@(test)
test_escalate_e2e_one_shot :: proc(t: ^testing.T) {
	reg: tools.Registry
	reg.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&reg, tools.Tool{name = "fake_tool", kind = .Read, run = mock_tool_run})
	esc_st := Esc_Mock{done_text = "escaped clean answer"}
	res := esc_turn(t, &esc_st, &reg, 14)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	testing.expect_value(t, res.stopped, "done")
	testing.expect(t, strings.contains(res.content, "escaped clean answer"))
	testing.expect_value(t, res.escalations, 1)
	testing.expect_value(t, res.escalate_model, "escmock/strong-model")
	// The expert was consulted exactly once: the weak model drives, the
	// escalation call is a sparse one-shot.
	testing.expect_value(t, esc_st.calls, 1)
}

@(test)
test_escalate_e2e_degrades_to_base :: proc(t: ^testing.T) {
	reg: tools.Registry
	reg.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&reg, tools.Tool{name = "fake_tool", kind = .Read, run = mock_tool_run})
	esc_st := Esc_Mock{fail = true}
	res := esc_turn(t, &esc_st, &reg, constants.LOOP_STOP_FIRES * 6)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	// The failed escalation silently degrades and the base model keeps
	// looping until the anti-loop stop lands.
	testing.expect_value(t, res.stopped, "loop")
	testing.expect_value(t, res.escalations, 1)
	// One attempt only, the same signature never re-escalates.
	testing.expect_value(t, esc_st.calls, 1)
}
