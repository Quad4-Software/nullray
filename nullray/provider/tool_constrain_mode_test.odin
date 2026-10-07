// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:http"

@(private)
constrain_mode_env_save :: proc() -> (saved: string, had: bool) {
	saved, had = os.lookup_env(constants.ENV_CONSTRAINED_MODE, context.temp_allocator)
	return saved, had
}

@(private)
constrain_mode_env_restore :: proc(saved: string, had: bool) {
	if had {
		os.set_env(constants.ENV_CONSTRAINED_MODE, saved)
	} else {
		os.unset_env(constants.ENV_CONSTRAINED_MODE)
	}
}

@(test)
test_constrained_mode_parse :: proc(t: ^testing.T) {
	testing.expect(t, constrained_mode_parse("strict") == .Strict)
	testing.expect(t, constrained_mode_parse(" SHAPE ") == .Shape)
	testing.expect(t, constrained_mode_parse("late") == .Late)
	testing.expect(t, constrained_mode_parse("two-phase") == .Late)
	testing.expect(t, constrained_mode_parse("bogus") == .Unset)
	testing.expect(t, constrained_mode_parse("") == .Unset)
	testing.expect_value(t, constrained_mode_name(.Strict), "strict")
	testing.expect_value(t, constrained_mode_name(.Shape), "shape")
	testing.expect_value(t, constrained_mode_name(.Late), "late")
	testing.expect_value(t, constrained_mode_name(.Unset), "")
}

@(test)
test_shape_grammar_locks_names_frees_values :: proc(t: ^testing.T) {
	g, ok := tool_grammar_build_shape(CONSTRAIN_TEST_TOOLS, true, context.temp_allocator)
	testing.expect(t, ok)
	// Envelope and tool names stay literal.
	testing.expect(t, strings.contains(g, `\"tool_calls\"`))
	testing.expect(t, strings.contains(g, `\"tool_call\"`))
	testing.expect(t, strings.contains(g, `\"response\"`))
	testing.expect(t, strings.contains(g, `\"read_file\"`))
	testing.expect(t, strings.contains(g, `\"shell\"`))
	// Argument key names are still structural.
	testing.expect(t, strings.contains(g, `\"path\"`))
	testing.expect(t, strings.contains(g, `\"cmd\"`))
	// Enum members inside arguments degrade to free strings.
	testing.expect(t, !strings.contains(g, `\"head\"`))
	testing.expect(t, !strings.contains(g, `\"tail\"`))
	testing.expect(t, !strings.contains(g, `\"all\"`))

	// Strict still carries the enum literals.
	gs, ok2 := tool_grammar_build(CONSTRAIN_TEST_TOOLS, true, context.temp_allocator)
	testing.expect(t, ok2)
	testing.expect(t, strings.contains(gs, `\"head\"`))
}

@(test)
test_shape_schema_envelope :: proc(t: ^testing.T) {
	s, ok := tool_schema_envelope_json(CONSTRAIN_TEST_TOOLS, true, true)
	testing.expect(t, ok)
	// Tool names keep their const lock on the envelope.
	testing.expect(t, strings.contains(s, `"const":"read_file"`))
	testing.expect(t, strings.contains(s, `"const":"shell"`))
	testing.expect(t, strings.contains(s, `"required"`))
	// Enum locks inside arguments are stripped.
	testing.expect(t, !strings.contains(s, `"enum"`))
	testing.expect(t, !strings.contains(s, `"head"`))
	testing.expect(t, !strings.contains(s, `"tail"`))
	// Types stay, so argument shape is still constrained.
	testing.expect(t, strings.contains(s, `"type":"string"`))
}

@(test)
test_constrained_mode_env :: proc(t: ^testing.T) {
	saved, had := constrain_mode_env_save()
	defer constrain_mode_env_restore(saved, had)
	saved_ct, had_ct := os.lookup_env(ENV_CONSTRAINED_TOOLS, context.temp_allocator)
	defer if had_ct {
		os.set_env(ENV_CONSTRAINED_TOOLS, saved_ct)
	} else {
		os.unset_env(ENV_CONSTRAINED_TOOLS)
	}
	os.unset_env(ENV_CONSTRAINED_TOOLS)
	profile_install_for_test(`{"profiles":[]}`)
	defer profile_reset_for_test()

	p := Provider{id = "llamacpp"}

	// Auto default: weak model ids get shape, known-strong ids get strict.
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Shape)
	testing.expect(t, constrained_mode_effective(&p, "llama3.1:70b") == .Strict)
	testing.expect(t, constrained_mode_effective(&p, "phi-4-mini") == .Shape)
	testing.expect(t, constrained_mode_effective(&p, "mistral") == .Shape)

	// Probed parameter size wins over the model id.
	p.caps.parameter_size = "70.6B"
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Strict)
	p.caps.parameter_size = "1.7B"
	testing.expect(t, constrained_mode_effective(&p, "llama3.1:70b") == .Shape)
	p.caps.parameter_size = ""

	// Env mode pins outright and implies enabled.
	os.set_env(constants.ENV_CONSTRAINED_MODE, "late")
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Late)
	testing.expect(t, constrained_tools_enabled(&p, "qwen3:8b"))
	os.set_env(constants.ENV_CONSTRAINED_MODE, "strict")
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Strict)

	// Profile mode wins over the auto default, env still wins over profile.
	os.unset_env(constants.ENV_CONSTRAINED_MODE)
	profile_install_for_test(`{"profiles":[{"match":"qwen*","constrained_mode":"late"}]}`)
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Late)
	testing.expect(t, constrained_tools_enabled(&p, "qwen3:8b"))
	os.set_env(constants.ENV_CONSTRAINED_MODE, "shape")
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Shape)

	// The session latch beats every other source.
	p.constrained_late = true
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Late)
}

@(test)
test_late_mode_retry :: proc(t: ^testing.T) {
	saved, had := constrain_mode_env_save()
	defer constrain_mode_env_restore(saved, had)
	saved_ct, had_ct := os.lookup_env(ENV_CONSTRAINED_TOOLS, context.temp_allocator)
	defer if had_ct {
		os.set_env(ENV_CONSTRAINED_TOOLS, saved_ct)
	} else {
		os.unset_env(ENV_CONSTRAINED_TOOLS)
	}
	saved_probe, had_probe := os.lookup_env(constants.ENV_LOCAL_PROBE, context.temp_allocator)
	defer if had_probe {
		os.set_env(constants.ENV_LOCAL_PROBE, saved_probe)
	} else {
		os.unset_env(constants.ENV_LOCAL_PROBE)
	}
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	os.set_env(ENV_CONSTRAINED_TOOLS, "1")
	os.set_env(constants.ENV_CONSTRAINED_MODE, "late")
	profile_install_for_test(`{"profiles":[]}`)
	defer profile_reset_for_test()

	p := Provider{id = "llamacpp", base_url = "http://127.0.0.1:1"}
	req := Chat_Request{
		messages = []Message{{role = .User, content = "hi"}},
		tools_json = CONSTRAIN_TEST_TOOLS,
	}

	// Phase 1 sends no constraint field at all.
	body := build_openai_chat_body(&p, req, "qwen3:8b", false, nil)
	testing.expect(t, !strings.contains(body, `"grammar"`))
	testing.expect(t, !constrained_tools_sent(&p, "qwen3:8b", req))

	// Phase 2 (constrained_retry set) pins the strict grammar.
	req2 := req
	req2.constrained_retry = true
	body2 := build_openai_chat_body(&p, req2, "qwen3:8b", false, nil)
	testing.expect(t, strings.contains(body2, `"grammar":"`))
	testing.expect(t, strings.contains(body2, `root ::=`))
	testing.expect(t, constrained_tools_sent(&p, "qwen3:8b", req2))

	// The resend predicate fires on malformed args once, never twice.
	bad := []Tool_Call{{name = "read_file", arguments = `{"path":`}}
	good := []Tool_Call{{name = "read_file", arguments = `{"path":"/x"}`}}
	testing.expect(t, tool_call_args_malformed(bad))
	testing.expect(t, !tool_call_args_malformed(good))
	testing.expect(t, !tool_call_args_malformed(nil))
	testing.expect(t, constrained_late_resend(&p, "qwen3:8b", req, true))
	testing.expect(t, !constrained_late_resend(&p, "qwen3:8b", req, false))
	testing.expect(t, !constrained_late_resend(&p, "qwen3:8b", req2, true))

	// A no-tools request never resends.
	plain := Chat_Request{messages = []Message{{role = .User, content = "hi"}}}
	testing.expect(t, !constrained_late_resend(&p, "qwen3:8b", plain, true))

	// Shape mode does not resend either, only late.
	os.set_env(constants.ENV_CONSTRAINED_MODE, "shape")
	testing.expect(t, !constrained_late_resend(&p, "qwen3:8b", req, true))
}

@(test)
test_shape_reject_falls_back_late :: proc(t: ^testing.T) {
	saved, had := constrain_mode_env_save()
	defer constrain_mode_env_restore(saved, had)
	os.unset_env(constants.ENV_CONSTRAINED_MODE)
	profile_install_for_test(`{"profiles":[]}`)
	defer profile_reset_for_test()

	p := Provider{id = "llamacpp"}
	rej := http.Response{ok = false, status = 500, body = `{"error":"Cannot specify grammar with tools"}`}

	// Weak model sends shape; a rejection degrades to late, not off.
	constrained_disable(&p, rej, "qwen3:8b")
	testing.expect(t, p.constrained_late)
	testing.expect(t, !p.constrained_off)
	testing.expect(t, constrained_mode_effective(&p, "qwen3:8b") == .Late)

	// A second rejection under late drops the constraint outright.
	constrained_disable(&p, rej, "qwen3:8b")
	testing.expect(t, p.constrained_off)

	// A strong model sends strict; a rejection goes straight to off.
	p2 := Provider{id = "llamacpp"}
	constrained_disable(&p2, rej, "llama3.1:70b")
	testing.expect(t, !p2.constrained_late)
	testing.expect(t, p2.constrained_off)
}

@(test)
test_constrained_mode_profile :: proc(t: ^testing.T) {
	profiles := profile_parse(
		`{"profiles":[{"match":"qwen*","constrained_mode":"late"},{"match":"x","constrained_tools":true}]}`,
		context.allocator,
	)
	defer profiles_free(profiles)
	testing.expect_value(t, len(profiles), 2)
	testing.expect(t, profiles[0].constrained_mode == .Late)
	testing.expect(t, profiles[1].constrained_mode == .Unset)

	out := profile_serialize(profiles, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"constrained_mode":"late"`))
	testing.expect(t, !strings.contains(out, `"constrained_mode":"unset"`))

	// Round trip: the serialized text parses back to the same mode.
	again := profile_parse(out, context.allocator)
	defer profiles_free(again)
	testing.expect_value(t, len(again), 2)
	testing.expect(t, again[0].constrained_mode == .Late)
	testing.expect(t, again[1].constrained_mode == .Unset)
}
