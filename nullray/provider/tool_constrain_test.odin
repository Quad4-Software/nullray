// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:http"

@(private)
CONSTRAIN_TEST_TOOLS :: `[{"type":"function","function":{"name":"read_file","description":"read","parameters":{"type":"object","properties":{"path":{"type":"string"},"limit":{"type":"integer"},"mode":{"type":"string","enum":["head","tail","all"]}},"required":["path"],"additionalProperties":false}}},{"type":"function","function":{"name":"shell","parameters":{"type":"object","properties":{"cmd":{"type":"string"},"env":{"type":"object","properties":{"k":{"type":"string"}},"required":["k"]},"tags":{"type":"array","items":{"type":"string"}},"dry":{"type":"boolean"}},"required":["cmd"]}}}]`

@(private)
constrain_env_save :: proc() -> (saved: string, had: bool) {
	saved, had = os.lookup_env(ENV_CONSTRAINED_TOOLS, context.temp_allocator)
	return saved, had
}

@(private)
constrain_env_restore :: proc(saved: string, had: bool) {
	if had {
		os.set_env(ENV_CONSTRAINED_TOOLS, saved)
	} else {
		os.unset_env(ENV_CONSTRAINED_TOOLS)
	}
}

@(test)
test_tool_grammar_basic :: proc(t: ^testing.T) {
	g, ok := tool_grammar_build(CONSTRAIN_TEST_TOOLS, true, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(g, "root ::="))
	testing.expect(t, strings.contains(g, `\"tool_calls\"`))
	testing.expect(t, strings.contains(g, `\"tool_call\"`))
	testing.expect(t, strings.contains(g, `\"response\"`))
	// Tool names, argument keys, and enum members appear as JSON escaped
	// literals (marshal adds the inner quotes the wire bytes carry).
	testing.expect(t, strings.contains(g, `\"read_file\"`))
	testing.expect(t, strings.contains(g, `\"shell\"`))
	testing.expect(t, strings.contains(g, `\"path\"`))
	testing.expect(t, strings.contains(g, `\"cmd\"`))
	testing.expect(t, strings.contains(g, `\"head\"`))
	testing.expect(t, strings.contains(g, `\"tail\"`))
}

@(test)
test_tool_grammar_balanced :: proc(t: ^testing.T) {
	g, ok := tool_grammar_build(CONSTRAIN_TEST_TOOLS, true, context.temp_allocator)
	testing.expect(t, ok)
	// Every rule line carries ::= and brackets balance across the grammar.
	rule_count := 0
	rest := g
	for len(rest) > 0 {
		line := rest
		if idx := strings.index_byte(rest, '\n'); idx >= 0 {
			line = rest[:idx]
			rest = rest[idx + 1:]
		} else {
			rest = ""
		}
		if len(strings.trim_space(line)) == 0 {
			continue
		}
		testing.expect(t, strings.contains(line, "::="))
		rule_count += 1
	}
	testing.expect(t, rule_count > 8)
	parens, brackets := 0, 0
	in_class, in_lit, esc := false, false, false
	for r in g {
		if esc {
			esc = false
			continue
		}
		if r == '\\' {
			esc = true
			continue
		}
		if in_class {
			if r == ']' {
				in_class = false
			}
			continue
		}
		if in_lit {
			if r == '"' {
				in_lit = false
			}
			continue
		}
		if r == '"' {
			in_lit = true
			continue
		}
		switch r {
		case '[':
			in_class = true
		case '(':
			parens += 1
		case ')':
			parens -= 1
		case '{':
			brackets += 1
		case '}':
			brackets -= 1
		}
	}
	testing.expect_value(t, parens, 0)
	testing.expect_value(t, brackets, 0)
}

@(test)
test_tool_grammar_required_vs_optional :: proc(t: ^testing.T) {
	// path is required so its pair is mandatory in the args rule, the
	// optional members sit in a ("," ws ...)* tail instead.
	tools := `[{"type":"function","function":{"name":"f","parameters":{"type":"object","properties":{"a":{"type":"string"},"b":{"type":"number"}},"required":["a"]}}}]`
	g, ok := tool_grammar_build(tools, true, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(g, `\"a\"" ws ":" ws`))
	testing.expect(t, strings.contains(g, `("," ws (`))
	testing.expect(t, strings.contains(g, `\"b\"" ws ":" ws`))
}

@(test)
test_tool_grammar_single_call_list :: proc(t: ^testing.T) {
	g, ok := tool_grammar_build(CONSTRAIN_TEST_TOOLS, false, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(g, `call-list ::= "[" ws call "]" ws`))
}

@(test)
test_tool_grammar_bad_input :: proc(t: ^testing.T) {
	_, ok := tool_grammar_build("not json", true, context.temp_allocator)
	testing.expect(t, !ok)
	_, ok2 := tool_grammar_build(`[]`, true, context.temp_allocator)
	testing.expect(t, !ok2)
	_, ok3 := tool_grammar_build(`[{"type":"function","function":{"parameters":{}}}]`, true, context.temp_allocator)
	testing.expect(t, !ok3)
}

@(test)
test_tool_schema_envelope :: proc(t: ^testing.T) {
	s, ok := tool_schema_envelope_json(CONSTRAIN_TEST_TOOLS, true)
	testing.expect(t, ok)
	doc, perr := json.parse_string(s, .JSON, allocator = context.temp_allocator)
	testing.expect(t, perr == .None)
	root, rok := doc.(json.Object)
	testing.expect(t, rok)
	any_v, has := root["anyOf"]
	testing.expect(t, has)
	any_arr, aok := any_v.(json.Array)
	testing.expect(t, aok && len(any_arr) == 2)
	testing.expect(t, strings.contains(s, `"read_file"`))
	testing.expect(t, strings.contains(s, `"response"`))
	// one_tool_per_turn collapses the array to a single call.
	s2, ok2 := tool_schema_envelope_json(CONSTRAIN_TEST_TOOLS, false)
	testing.expect(t, ok2)
	testing.expect(t, strings.contains(s2, `"maxItems":1`))
}

@(test)
test_constrained_gate :: proc(t: ^testing.T) {
	saved, had := constrain_env_save()
	defer constrain_env_restore(saved, had)
	os.unset_env(ENV_CONSTRAINED_TOOLS)

	p := Provider{id = "llamacpp"}
	testing.expect(t, constrained_mechanism("llamacpp") == .Grammar)
	testing.expect(t, constrained_mechanism("ollama") == .Json_Schema)
	testing.expect(t, constrained_mechanism("lmstudio") == .Json_Schema)
	testing.expect(t, constrained_mechanism("openai") == .None)

	// Default off without a profile flag or env.
	profile_install_for_test(`{"profiles":[]}`)
	defer profile_reset_for_test()
	testing.expect(t, !constrained_tools_enabled(&p, "anymodel"))

	// Env forces on for capable providers.
	os.set_env(ENV_CONSTRAINED_TOOLS, "1")
	testing.expect(t, constrained_tools_enabled(&p, "anymodel"))
	cloud := Provider{id = "openai"}
	testing.expect(t, !constrained_tools_enabled(&cloud, "anymodel"))
	os.set_env(ENV_CONSTRAINED_TOOLS, "0")
	testing.expect(t, !constrained_tools_enabled(&p, "anymodel"))

	// Profile flag enables per model.
	os.unset_env(ENV_CONSTRAINED_TOOLS)
	profile_install_for_test(`{"profiles":[{"match":"qwen*","constrained_tools":true}]}`)
	testing.expect(t, constrained_tools_enabled(&p, "qwen3:8b"))
	testing.expect(t, !constrained_tools_enabled(&p, "mistral:7b"))

	// A session rejection disables despite env/profile.
	os.set_env(ENV_CONSTRAINED_TOOLS, "1")
	p.constrained_off = true
	testing.expect(t, !constrained_tools_enabled(&p, "qwen3:8b"))
}

@(test)
test_constrained_body_wiring :: proc(t: ^testing.T) {
	saved, had := constrain_env_save()
	defer constrain_env_restore(saved, had)
	saved_probe, had_probe := os.lookup_env(constants.ENV_LOCAL_PROBE, context.temp_allocator)
	defer if had_probe {
		os.set_env(constants.ENV_LOCAL_PROBE, saved_probe)
	} else {
		os.unset_env(constants.ENV_LOCAL_PROBE)
	}
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	os.set_env(ENV_CONSTRAINED_TOOLS, "1")
	profile_install_for_test(`{"profiles":[]}`)
	defer profile_reset_for_test()

	req := Chat_Request{
		messages = []Message{{role = .User, content = "hi"}},
		tools_json = CONSTRAIN_TEST_TOOLS,
	}

	// llamacpp carries the GBNF grammar field.
	lp := Provider{id = "llamacpp", base_url = "http://127.0.0.1:1"}
	body := build_openai_chat_body(&lp, req, "mistral:7b", false, nil)
	testing.expect(t, strings.contains(body, `"grammar":"`))
	testing.expect(t, strings.contains(body, `root ::=`))

	// ollama carries response_format json_schema, no grammar field.
	op := Provider{id = "ollama", base_url = "http://127.0.0.1:1"}
	obody := build_openai_chat_body(&op, req, "mistral:7b", false, nil)
	testing.expect(t, strings.contains(obody, `"response_format":{"type":"json_schema"`))
	testing.expect(t, !strings.contains(obody, `"grammar"`))

	// After a session rejection the field is dropped.
	op.constrained_off = true
	obody2 := build_openai_chat_body(&op, req, "mistral:7b", false, nil)
	testing.expect(t, !strings.contains(obody2, `"response_format"`))

	// Cloud providers never get the field even with the env flag.
	cp := Provider{id = "openai", base_url = "http://127.0.0.1:1"}
	cbody := build_openai_chat_body(&cp, req, "gpt-5", false, nil)
	testing.expect(t, !strings.contains(cbody, `"grammar"`))
	testing.expect(t, !strings.contains(cbody, `"response_format"`))

	// No tools in the request, no constraint.
	plain := Chat_Request{messages = []Message{{role = .User, content = "hi"}}}
	nbody := build_openai_chat_body(&lp, plain, "mistral:7b", false, nil)
	testing.expect(t, !strings.contains(nbody, `"grammar"`))
}

@(test)
test_constrained_rejected :: proc(t: ^testing.T) {
	testing.expect(t, !constrained_rejected(http.Response{ok = true, status = 200}))
	// llama.cpp "Cannot specify grammar with tools" style rejection.
	bad := http.Response{
		ok = false,
		status = 500,
		body = `{"error":{"message":"Cannot specify grammar with tools"}}`,
	}
	testing.expect(t, constrained_rejected(bad))
	f400 := http.Response{ok = false, status = 400, body = `{"error":"invalid response_format"}`}
	testing.expect(t, constrained_rejected(f400))
	// Unrelated failures never disable the constraint.
	ctx := http.Response{ok = false, status = 400, body = `{"error":"the request exceeds the available context size"}`}
	testing.expect(t, !constrained_rejected(ctx))
	r429 := http.Response{ok = false, status = 429, body = `{"error":"rate limited"}`}
	testing.expect(t, !constrained_rejected(r429))
	transport := http.Response{ok = false, status = 0, err = "connection refused"}
	testing.expect(t, !constrained_rejected(transport))
}

@(test)
test_constrained_profile_parse :: proc(t: ^testing.T) {
	profiles := profile_parse(
		`{"profiles":[{"match":"qwen*","constrained_tools":true},{"match":"x","constrained_tools":false}]}`,
		context.allocator,
	)
	defer profiles_free(profiles)
	testing.expect_value(t, len(profiles), 2)
	testing.expect(t, profiles[0].constrained_tools_set && profiles[0].constrained_tools)
	testing.expect(t, profiles[1].constrained_tools_set && !profiles[1].constrained_tools)

	out := profile_serialize(profiles, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"constrained_tools":true`))
	testing.expect(t, strings.contains(out, `"constrained_tools":false`))
}
