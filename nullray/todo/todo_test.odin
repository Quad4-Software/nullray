// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package todo

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

@(private)
Test_Ws :: struct {
	ws:   string,
	prev: string,
	had:  bool,
	sid:  string,
}

@(private)
test_ws_begin :: proc(t: ^testing.T, name: string) -> Test_Ws {
	ctx: Test_Ws
	base := "/tmp"
	if td, ok := os.lookup_env("TMPDIR", context.temp_allocator); ok && len(td) > 0 {
		base = td
	}
	ctx.ws = fmt.tprintf("%s/nullray-todo-test-%d-%s", base, time.time_to_unix(time.now()), name)
	_ = os.remove_all(ctx.ws)
	testing.expect(t, os.make_directory_all(ctx.ws) == nil)
	ctx.prev, ctx.had = os.lookup_env(constants.ENV_WORKSPACE, context.allocator)
	os.set_env(constants.ENV_WORKSPACE, ctx.ws)
	// Sid strings must outlive temp_allocator reuse across tests.
	ctx.sid = strings.clone(fmt.tprintf("test-%s", name), context.allocator)
	return ctx
}

@(private)
test_ws_end :: proc(ctx: Test_Ws) {
	unload(ctx.sid)
	delete(ctx.sid)
	if ctx.had {
		os.set_env(constants.ENV_WORKSPACE, ctx.prev)
		delete(ctx.prev)
	} else {
		os.unset_env(constants.ENV_WORKSPACE)
	}
	os.remove_all(ctx.ws)
}

@(test)
test_add_update :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "addupd")
	defer test_ws_end(ctx)

	id, err := add(ctx.sid, "write tests", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, id, "t1")

	err = update(ctx.sid, "t1", "in_progress", "", false, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")

	err = update(ctx.sid, "t1", "done", "shipped", true, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")

	err = update(ctx.sid, "nope", "done", "", false, nil, false, context.temp_allocator)
	testing.expect(t, strings.contains(err, "no todo item"))

	err = update(ctx.sid, "t1", "bogus", "", false, nil, false, context.temp_allocator)
	testing.expect(t, strings.contains(err, "bad status"))
}

@(test)
test_write_sync_semantics :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "sync")
	defer test_ws_end(ctx)

	items := []Sync_Item{
		{text = "first task"},
		{text = "second task", status = "in_progress"},
	}
	err := sync_items(ctx.sid, items, context.temp_allocator)
	testing.expect_value(t, err, "")

	// Re-sync matching by exact text preserves ids; absent item is
	// cancelled, not deleted.
	items2 := []Sync_Item{
		{id = "t1", text = "first task", status = "done"},
		{text = "third task"},
	}
	err = sync_items(ctx.sid, items2, context.temp_allocator)
	testing.expect_value(t, err, "")

	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t1 [x] first task"))
	testing.expect(t, strings.contains(view, "t2 [-] second task"))
	testing.expect(t, strings.contains(view, "t3 [ ] third task"))
	testing.expect(t, strings.contains(view, "1 open / 3 total"))
}

@(test)
test_blocked_on_resolution :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "blocked")
	defer test_ws_end(ctx)

	_, err := add(ctx.sid, "parent", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	deps := []string{"t1"}
	_, err = add(ctx.sid, "child", deps, context.temp_allocator)
	testing.expect_value(t, err, "")

	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t2 [!] child (blocked_on: t1)"))

	// Closing the blocker unblocks the dependent marker.
	err = update(ctx.sid, "t1", "done", "", false, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")
	view = list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t2 [ ] child (blocked_on: t1)"))
}

@(test)
test_cap_items :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "cap")
	defer test_ws_end(ctx)

	for i in 0 ..< constants.TODO_MAX_ITEMS {
		_, err := add(ctx.sid, fmt.tprintf("task %d", i), nil, context.temp_allocator)
		testing.expect_value(t, err, "")
	}
	_, err := add(ctx.sid, "one too many", nil, context.temp_allocator)
	testing.expect(t, strings.contains(err, "full"))
}

@(test)
test_stale_counter :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "stale")
	defer test_ws_end(ctx)

	// No open items: mark_turn never advances the counter.
	mark_turn(ctx.sid)
	mark_turn(ctx.sid)
	testing.expect_value(t, turns_since_touch(ctx.sid), 0)

	_, err := add(ctx.sid, "open work", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	// add counts as a touch via post_mutation.
	testing.expect_value(t, turns_since_touch(ctx.sid), 0)

	mark_turn(ctx.sid)
	testing.expect_value(t, turns_since_touch(ctx.sid), 1)
	block := prompt_block(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(block, "<open_tasks>"))
	testing.expect(t, strings.contains(block, "t1 [ ] open work"))
	testing.expect(t, strings.contains(block, "todo_write/todo_update"))
	testing.expect(t, !strings.contains(block, "stale"))

	mark_turn(ctx.sid)
	block = prompt_block(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(block, "stale: 2 turns"))

	mark_tool_use(ctx.sid)
	testing.expect_value(t, turns_since_touch(ctx.sid), 0)

	// Completing the only item stops injection.
	err = update(ctx.sid, "t1", "done", "", false, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")
	block = prompt_block(ctx.sid, context.temp_allocator)
	testing.expect_value(t, block, "")
	testing.expect(t, take_completed_notice(ctx.sid))
	testing.expect(t, !take_completed_notice(ctx.sid))
}

@(test)
test_persistence_roundtrip :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "persist")
	defer test_ws_end(ctx)

	deps := []string{"t1"}
	_, err := add(ctx.sid, "alpha", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	_, err = add(ctx.sid, "beta", deps, context.temp_allocator)
	testing.expect_value(t, err, "")
	err = update(ctx.sid, "t1", "done", "shipped", true, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")

	unload(ctx.sid)

	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t1 [x] alpha"))
	testing.expect(t, strings.contains(view, "t2 [ ] beta (blocked_on: t1)"))
	testing.expect(t, strings.contains(view, "note: shipped"))

	// Ids keep incrementing past the reloaded seq.
	id, aerr := add(ctx.sid, "gamma", nil, context.temp_allocator)
	testing.expect_value(t, aerr, "")
	testing.expect_value(t, id, "t3")
}

@(test)
test_compact_view_format :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "compact")
	defer test_ws_end(ctx)

	_, err := add(ctx.sid, "open one", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	_, err = add(ctx.sid, "closed one", nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	err = update(ctx.sid, "t2", "done", "", false, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")

	out := summary_compact(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(out, "t1 [ ] open one"))
	testing.expect(t, !strings.contains(out, "closed one"))
}

@(test)
test_sync_atomic_on_bad_status :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "atomic")
	defer test_ws_end(ctx)

	_, err := add(ctx.sid, "keep me", nil, context.temp_allocator)
	testing.expect_value(t, err, "")

	// First entry valid, second carries a bad status: the sync must not
	// partially apply (validate-first, then apply).
	items := []Sync_Item{
		{id = "t1", text = "renamed", status = "done"},
		{text = "new task", status = "bogus"},
	}
	err = sync_items(ctx.sid, items, context.temp_allocator)
	testing.expect(t, strings.contains(err, "bad status"))

	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t1 [ ] keep me"))
	testing.expect(t, !strings.contains(view, "new task"))
}

@(test)
test_sync_cap_counts_only_applied :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "capcount")
	defer test_ws_end(ctx)

	// Fill to one below the cap.
	for i in 0 ..< constants.TODO_MAX_ITEMS - 1 {
		_, err := add(ctx.sid, fmt.tprintf("task %d", i), nil, context.temp_allocator)
		testing.expect_value(t, err, "")
	}
	// One new item plus one entry the apply loop would skip (unknown id,
	// blank text): the cap check must count only what the loop adds.
	items := []Sync_Item{
		{text = "real new task"},
		{id = "t9999", text = ""},
		{id = "t9998", text = "   "},
	}
	err := sync_items(ctx.sid, items, context.temp_allocator)
	testing.expect_value(t, err, "")
	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "real new task"))
	// Now at the cap; another new item must be refused.
	items2 := []Sync_Item{{text = "overflow"}}
	err = sync_items(ctx.sid, items2, context.temp_allocator)
	testing.expect(t, strings.contains(err, "exceed"))
}

@(test)
test_self_dep_refused_and_unknown_dep_ok :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "selfdep")
	defer test_ws_end(ctx)

	_, err := add(ctx.sid, "solo", nil, context.temp_allocator)
	testing.expect_value(t, err, "")

	// Self-dependency refused on update.
	err = update(ctx.sid, "t1", "", "", false, []string{"t1"}, true, context.temp_allocator)
	testing.expect(t, strings.contains(err, "itself"))

	// A dep on a nonexistent id is stored but does not block the item.
	deps := []string{"t999"}
	_, err = add(ctx.sid, "phantom dep", deps, context.temp_allocator)
	testing.expect_value(t, err, "")
	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, "t2 [ ] phantom dep"))

	// Self-dep refused in sync payloads.
	items := []Sync_Item{{id = "t1", text = "solo", blocked_on = []string{"t1"}, blocked_on_set = true}}
	err = sync_items(ctx.sid, items, context.temp_allocator)
	testing.expect(t, strings.contains(err, "itself"))
}

@(test)
test_persist_control_chars_roundtrip :: proc(t: ^testing.T) {
	ctx := test_ws_begin(t, "ctrl")
	defer test_ws_end(ctx)

	// Control chars that %q would have escaped as \a, \v, \xNN (invalid
	// JSON) plus quotes, backslashes and unicode must survive a save/load.
	nasty := "ctrl \x07\x1b\x0b \"quoted\" \\ tab\t unicode \u00e9"
	_, err := add(ctx.sid, nasty, nil, context.temp_allocator)
	testing.expect_value(t, err, "")
	err = update(ctx.sid, "t1", "", nasty, true, nil, false, context.temp_allocator)
	testing.expect_value(t, err, "")

	unload(ctx.sid)

	view := list_view(ctx.sid, context.temp_allocator)
	testing.expect(t, strings.contains(view, nasty), view)
}

@(test)
test_disabled_env :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_TODO, context.allocator)
	os.set_env(constants.ENV_TODO, "0")
	defer {
		if had {
			os.set_env(constants.ENV_TODO, prev)
			delete(prev)
		} else {
			os.unset_env(constants.ENV_TODO)
		}
	}
	testing.expect(t, !enabled())
}
