// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Watch tests: fingerprint/delta logic, add/list/rm persistence through the
durable job store, budget enforcement, and the no-delta-no-digest path.
*/

package schedule

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(private)
watch_test_ws :: proc(t: ^testing.T) -> string {
	ws := "/tmp/nullray-watch-test-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	sandbox.workspace_override_set(ws)
	return ws
}

@(private)
watch_test_done :: proc(ws: string) {
	sandbox.workspace_override_clear()
	_ = os.remove_all(ws)
}

@(test)
test_watch_fingerprint_set_semantics :: proc(t: ^testing.T) {
	a := watch_fingerprint({"b", "a", "c"}, context.temp_allocator)
	b := watch_fingerprint({"c", "a", "b"}, context.temp_allocator)
	c := watch_fingerprint({"a", "b"}, context.temp_allocator)
	testing.expect_value(t, a, b)
	testing.expect(t, a != c)
	testing.expect_value(t, len(a), 16)
}

@(test)
test_watch_items_normalize :: proc(t: ^testing.T) {
	doc, _ := json.parse_string(`{"items":["CVE-1","CVE-2","CVE-1"]}`, .JSON, allocator = context.temp_allocator)
	items, err := watch_items_normalize(doc.(json.Object)["items"], context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(items), 3)
	// String carrying a JSON array.
	doc2, _ := json.parse_string(`{"items":"[\"a\", \"b\"]"}`, .JSON, allocator = context.temp_allocator)
	items2, err2 := watch_items_normalize(doc2.(json.Object)["items"], context.temp_allocator)
	testing.expect_value(t, err2, "")
	testing.expect_value(t, len(items2), 2)
	// Comma list.
	doc3, _ := json.parse_string(`{"items":"a, b\nc"}`, .JSON, allocator = context.temp_allocator)
	items3, _ := watch_items_normalize(doc3.(json.Object)["items"], context.temp_allocator)
	testing.expect_value(t, len(items3), 3)
	// Objects prefer an id field.
	doc4, _ := json.parse_string(`{"items":[{"id":"CVE-9","score":9.8}]}`, .JSON, allocator = context.temp_allocator)
	items4, _ := watch_items_normalize(doc4.(json.Object)["items"], context.temp_allocator)
	testing.expect_value(t, len(items4), 1)
	testing.expect_value(t, items4[0], "CVE-9")
}

@(test)
test_watch_add_checkpoint_delta :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := watch_test_ws(t)
	defer watch_test_done(ws)
	now := i64(1000)
	id, err := watch_add("check CVE feeds", "every 2h", "", 0, 0, 0, now)
	testing.expect_value(t, err, "")
	testing.expect(t, id > 0)
	testing.expect(t, watch_exists(id))
	j, jok := job_lookup(id)
	testing.expect(t, jok)
	testing.expect(t, strings.contains(j.prompt, "watch_checkpoint"))
	testing.expect(t, strings.contains(j.prompt, "check CVE feeds"))

	items := []string{"CVE-1", "CVE-2"}
	report, n, cerr := watch_checkpoint(id, items, "first run", now, context.temp_allocator)
	testing.expect_value(t, cerr, "")
	testing.expect_value(t, n, 2)
	testing.expect(t, strings.contains(report, "2 new item"))

	// No delta: same set reports zero and writes no digest entry.
	report, n, cerr = watch_checkpoint(id, items, "again", now + 60, context.temp_allocator)
	testing.expect_value(t, cerr, "")
	testing.expect_value(t, n, 0)
	testing.expect(t, strings.contains(report, "no new items"))
	digest_path := watch_digest_path(id, context.temp_allocator)
	data, _ := os.read_entire_file(digest_path, context.temp_allocator)
	testing.expect(t, strings.count(string(data), "new)") == 1, string(data))

	// Partial overlap: only the unseen id counts.
	report, n, cerr = watch_checkpoint(id, {"CVE-2", "CVE-3"}, "delta", now + 120, context.temp_allocator)
	testing.expect_value(t, cerr, "")
	testing.expect_value(t, n, 1)
	testing.expect(t, strings.contains(report, "CVE-3"))
	testing.expect(t, !strings.contains(report, "CVE-1"))

	st, ok := watch_state_load(id, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, st.checks, 3)
	testing.expect_value(t, st.hits, 2)
	testing.expect_value(t, len(st.seen), 3)
}

@(test)
test_watch_unknown_checkpoint :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := watch_test_ws(t)
	defer watch_test_done(ws)
	_, n, err := watch_checkpoint(99, {"x"}, "", 1, context.temp_allocator)
	testing.expect_value(t, n, 0)
	testing.expect(t, strings.contains(err, "unknown watch"))
}

@(test)
test_watch_list_and_rm :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := watch_test_ws(t)
	defer watch_test_done(ws)
	now := i64(1000)
	id, err := watch_add("list me", "every 1h", "sess-x", 5, 4096, 0, now)
	testing.expect_value(t, err, "")
	text := watch_list_text(now, context.temp_allocator)
	testing.expect(t, strings.contains(text, "watch"))
	testing.expect(t, strings.contains(text, "every 1h"))
	testing.expect(t, strings.contains(text, "expires in"))
	testing.expect(t, strings.contains(text, "list me"))
	// rm drops both the job and the state dir.
	testing.expect(t, watch_rm(id))
	testing.expect(t, !watch_exists(id))
	_, jok := job_lookup(id)
	testing.expect(t, !jok)
	testing.expect(t, strings.contains(watch_list_text(now, context.temp_allocator), "no watches"))
}

@(test)
test_watch_budget_canonical :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := watch_test_ws(t)
	defer watch_test_done(ws)
	now := i64(1000)
	id, err := watch_add("budget", "every 1h", "", 0, 100, 0, now)
	testing.expect_value(t, err, "")
	// Under the cap: tokens accumulate, no note.
	note := watch_record_run(id, 60, now + 60, context.temp_allocator)
	testing.expect_value(t, note, "")
	_, jok := job_lookup(id)
	testing.expect(t, jok)
	// Over the cap: exhausted, job cancelled, note for the notifier.
	note = watch_record_run(id, 50, now + 120, context.temp_allocator)
	testing.expect(t, strings.contains(note, "token budget"))
	_, jok = job_lookup(id)
	testing.expect(t, !jok)
	// A spent watch refuses further checkpoints.
	_, n, cerr := watch_checkpoint(id, {"x"}, "", now + 180, context.temp_allocator)
	testing.expect_value(t, n, 0)
	testing.expect(t, strings.contains(cerr, "exhausted"))
	st, ok := watch_state_load(id, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, st.exhausted)
	testing.expect_value(t, st.tokens, i64(110))
}

@(test)
test_watch_id_from_tag :: proc(t: ^testing.T) {
	id, ok := watch_id_from_tag("job:7")
	testing.expect(t, ok)
	testing.expect_value(t, id, 7)
	_, ok = watch_id_from_tag("heartbeat")
	testing.expect(t, !ok)
	_, ok = watch_id_from_tag("job:x")
	testing.expect(t, !ok)
}

@(test)
test_watch_spec_parse :: proc(t: ^testing.T) {
	spec, rest, err := watch_spec_parse({"every 2h", "check x"}, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, spec, "every 2h")
	testing.expect_value(t, len(rest), 1)

	spec, rest, err = watch_spec_parse({"every", "30m", "p"}, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, spec, "every 30m")
	testing.expect_value(t, len(rest), 1)

	// Bare duration means every.
	spec, rest, err = watch_spec_parse({"2h", "p"}, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, spec, "every 2h")

	// Cron five-field.
	spec, rest, err = watch_spec_parse({"0", "8", "*", "*", "1", "p"}, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, spec, "0 8 * * 1")
	testing.expect_value(t, len(rest), 1)

	_, _, err = watch_spec_parse({"bogus"}, context.temp_allocator)
	testing.expect(t, len(err) > 0)
	_, _, err = watch_spec_parse(nil, context.temp_allocator)
	testing.expect(t, len(err) > 0)
}

@(test)
test_watch_store_reload_merge :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := watch_test_ws(t)
	defer watch_test_done(ws)
	g_persist = true
	defer { g_persist = false }
	now := i64(1000)
	id, err := watch_add("reload me", "every 2h", "", 0, 0, 0, now)
	testing.expect_value(t, err, "")
	testing.expect_value(t, job_count(), 1)
	// Simulate a second process: the store gains a foreign job and loses
	// ours, reload adopts and drops accordingly.
	path := scheduled_path(context.temp_allocator)
	other := `{"version":1,"jobs":[{"id":77,"spec":"every 5h","prompt":"external","session":"","one_shot":false,"max_runs":0,"run_count":0,"fail_count":0,"next_fire":2000,"expires":999999}]}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)other) == nil)
	jobs_reload_if_changed()
	testing.expect_value(t, job_count(), 1)
	j, ok := job_lookup(77)
	testing.expect(t, ok)
	testing.expect_value(t, j.prompt, "external")
	testing.expect(t, j.durable)
	_, wok := job_lookup(id)
	testing.expect(t, !wok)
	testing.expect_value(t, g_next_id, 78)
}
