// SPDX-License-Identifier: 0BSD
package agent

import "core:testing"

@(test)
test_mode_strings :: proc(t: ^testing.T) {
	m, ok := mode_from_string("ask")
	testing.expect(t, ok)
	testing.expect_value(t, m, Agent_Mode.Ask)
	testing.expect_value(t, mode_string(m), "ask")

	m2, ok2 := mode_from_string("PLAN")
	testing.expect(t, ok2)
	testing.expect_value(t, m2, Agent_Mode.Plan)
	testing.expect_value(t, mode_string(m2), "plan")

	m3, ok3 := mode_from_string("review")
	testing.expect(t, ok3)
	testing.expect_value(t, m3, Agent_Mode.Review)
	testing.expect_value(t, mode_string(m3), "review")

	_, ok4 := mode_from_string("nope")
	testing.expect(t, !ok4)

	p, pok := policy_from_string("model")
	testing.expect(t, pok)
	testing.expect_value(t, p, Mode_Policy.Model)
	testing.expect_value(t, policy_string(p), "model")
}

@(test)
test_detect_mode_request :: proc(t: ^testing.T) {
	text := "hello\nMODE plan\nworld"
	mode, found, cleaned := detect_mode_request(text)
	defer delete(cleaned)
	testing.expect(t, found)
	testing.expect_value(t, mode, Agent_Mode.Plan)
	testing.expect_value(t, cleaned, "hello\nworld")

	text2 := "x\nMODE review\ny"
	mode2, found2, cleaned2 := detect_mode_request(text2)
	defer delete(cleaned2)
	testing.expect(t, found2)
	testing.expect_value(t, mode2, Agent_Mode.Review)
}

@(test)
test_auto_suggest_mode :: proc(t: ^testing.T) {
	testing.expect_value(t, auto_suggest_mode("explain how this works"), Agent_Mode.Ask)
	testing.expect_value(t, auto_suggest_mode("design an approach"), Agent_Mode.Plan)
	testing.expect_value(t, auto_suggest_mode("review this PR"), Agent_Mode.Review)
	testing.expect_value(t, auto_suggest_mode("fix the bug"), Agent_Mode.Edit)
	testing.expect_value(t, auto_suggest_mode("hello"), Agent_Mode.Edit)
}

@(test)
test_tools_for_mode :: proc(t: ^testing.T) {
	w, s, r := tools_for_mode(.Ask)
	testing.expect(t, !w && !s && r)
	w2, s2, r2 := tools_for_mode(.Edit)
	testing.expect(t, w2 && s2 && r2)
	w3, s3, r3 := tools_for_mode(.Review)
	testing.expect(t, !w3 && !s3 && r3)
	w4, s4, r4 := tools_for_mode(.Plan)
	testing.expect(t, !w4 && !s4 && r4)
}
