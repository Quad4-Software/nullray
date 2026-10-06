// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ask

import "core:mem"
import "core:testing"
import "core:thread"
import "core:time"

// The requester thread uses its own context allocator. Copy answers into a
// fixed buffer so the test side never frees memory owned by the thread heap.
@(private)
T_Result :: struct {
	answer:    [256]u8,
	answer_len: int,
	ok:        bool,
	cancelled: bool,
}

@(private)
t_store_answer :: proc(r: ^T_Result, ans: string, ok, cancelled: bool) {
	n := min(len(ans), len(r.answer))
	mem.copy(&r.answer[0], raw_data(ans), n)
	r.answer_len = n
	r.ok = ok
	r.cancelled = cancelled
	delete(ans)
}

@(private)
t_req_text :: proc(data: rawptr) {
	r := cast(^T_Result)data
	ans, ok, canc := request(.Text, "q?", nil, false, 30)
	t_store_answer(r, ans, ok, canc)
}

@(private)
t_req_choice :: proc(data: rawptr) {
	r := cast(^T_Result)data
	ans, ok, canc := request(.Choice, "pick", []string{"alpha", "beta"}, false, 30)
	t_store_answer(r, ans, ok, canc)
}

@(private)
wait_challenge :: proc() -> bool {
	for _ in 0 ..< 200 {
		if has_pending() {
			return true
		}
		time.sleep(10 * time.Millisecond)
	}
	return false
}

@(test)
test_request_fulfill :: proc(t: ^testing.T) {
	set_ui_enabled(true)
	defer set_ui_enabled(false)
	r := new(T_Result)
	defer free(r)
	th := thread.create_and_start_with_data(r, t_req_text)
	testing.expect(t, th != nil)
	testing.expect(t, wait_challenge())
	active, id, kind, prompt, options, free_form := challenge_pending()
	defer delete(prompt)
	defer delete(options)
	testing.expect(t, active)
	testing.expect(t, kind == .Text)
	testing.expect_value(t, prompt, "q?")
	testing.expect(t, !free_form)
	testing.expect(t, fulfill(id, "hello"))
	thread.join(th)
	thread.destroy(th)
	testing.expect(t, r.ok)
	testing.expect(t, !r.cancelled)
	got := string(r.answer[:r.answer_len])
	testing.expect_value(t, got, "hello")
}

@(test)
test_request_cancel :: proc(t: ^testing.T) {
	set_ui_enabled(true)
	defer set_ui_enabled(false)
	r := new(T_Result)
	defer free(r)
	th := thread.create_and_start_with_data(r, t_req_text)
	testing.expect(t, th != nil)
	testing.expect(t, wait_challenge())
	active, id, _, prompt, options, _ := challenge_pending()
	delete(prompt)
	delete(options)
	testing.expect(t, active)
	testing.expect(t, cancel(id))
	thread.join(th)
	thread.destroy(th)
	testing.expect(t, !r.ok)
	testing.expect(t, r.cancelled)
}

@(test)
test_request_no_channel :: proc(t: ^testing.T) {
	set_ui_enabled(false)
	ans, ok, canc := request(.Text, "q?", nil, false, 5)
	defer delete(ans)
	testing.expect(t, !ok)
	testing.expect(t, !canc)
}

@(test)
test_choice_options_cloned :: proc(t: ^testing.T) {
	set_ui_enabled(true)
	defer set_ui_enabled(false)
	r := new(T_Result)
	defer free(r)
	th := thread.create_and_start_with_data(r, t_req_choice)
	testing.expect(t, th != nil)
	testing.expect(t, wait_challenge())
	active, id, kind, prompt, options, _ := challenge_pending()
	delete(prompt)
	testing.expect(t, active)
	testing.expect(t, kind == .Choice)
	testing.expect(t, len(options) == 2)
	defer {
		for o in options {
			delete(o)
		}
		delete(options)
	}
	testing.expect(t, fulfill(id, options[1]))
	thread.join(th)
	thread.destroy(th)
	testing.expect(t, r.ok)
	got := string(r.answer[:r.answer_len])
	testing.expect_value(t, got, "beta")
}

@(test)
test_secret_vault :: proc(t: ^testing.T) {
	defer secrets_clear()
	secret_put("TEST_KEY", "s3cr3t")
	testing.expect(t, secret_has("TEST_KEY"))
	v := secret_get("TEST_KEY")
	testing.expect_value(t, v, "s3cr3t")
	delete(v)
	secret_put("TEST_KEY", "r0tated")
	v2 := secret_get("TEST_KEY")
	testing.expect_value(t, v2, "r0tated")
	delete(v2)
	names := secret_names()
	defer {
		for n in names {
			delete(n)
		}
		delete(names)
	}
	found := false
	for n in names {
		if n == "TEST_KEY" {
			found = true
		}
	}
	testing.expect(t, found)
	testing.expect(t, secret_forget("TEST_KEY"))
	testing.expect(t, !secret_has("TEST_KEY"))
	testing.expect(t, !secret_forget("TEST_KEY"))
}
