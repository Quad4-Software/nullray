// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
CORVUS file-state tests: hash tracking, unchanged re-read stubs, overlap
dedup, post-edit invalidation, state block emit and skip, env gate, and a
20+ message transcript measured against plain diet.
*/

package agent

import "core:fmt"
import "core:hash"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:provider"

@(private)
corvus_read_result :: proc(path: string, lines: ..string) -> string {
	body := strings.join(lines, "\n", context.temp_allocator)
	return fmt.aprintf("path %s lines=%d bytes=%d threshold=low\n%s", path, len(lines), len(body), body)
}

// Pad the tail with neutral shell results so earlier reads leave the
// reference window and stay eligible for stubbing.
@(private)
corvus_pad :: proc(msgs: ^[dynamic]provider.Message, pairs: int) {
	base := len(msgs)
	for i in 0 ..< pairs {
		id := fmt.tprintf("p%d", base + i)
		cmd := fmt.tprintf(`{"command":"job-%d"}`, base + i)
		append(msgs, diet_asst("", diet_call(id, "run_shell", cmd)))
		append(msgs, diet_tool(id, "run_shell", fmt.tprintf("out %d", base + i)))
	}
}

@(test)
test_corvus_unchanged_reread_stubbed :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	body := corvus_read_result("/a", "alpha", "beta")
	defer delete(body)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/a"}`)))
	append(&msgs, diet_tool("c1", "read_file", body))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/a"}`)))
	append(&msgs, diet_tool("c2", "read_file", body))
	corvus_pad(&msgs, 4)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.corvus.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[4].content, CORVUS_STUB_PREFIX))
	testing.expect(t, strings.contains(d[4].content, "unchanged since msg 2"))
	testing.expect(t, strings.contains(d[2].content, "alpha"))
	// First delivery stays, real history untouched.
	testing.expect(t, strings.contains(msgs[4].content, "beta"))
	// State block rides the last position with the tracked hash.
	last := d[len(d) - 1].content
	testing.expect(t, strings.contains(last, CORVUS_STATE_MARK))
	want := fmt.tprintf("/a %x", hash.fnv64a(transmute([]byte)body))
	testing.expect(t, strings.contains(last, want))
	testing.expect(t, st.corvus.saved_chars > 0)
	testing.expect(t, diet_pairing_ok(d[:]))
}

@(test)
test_corvus_overlap_covered :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	full := corvus_read_result("/f", "l1", "l2", "l3", "l4", "l5", "l6")
	defer delete(full)
	part := corvus_read_result("/f", "l3", "l4")
	defer delete(part)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/f"}`)))
	append(&msgs, diet_tool("c1", "read_file", full))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/f","offset":3,"limit":2}`)))
	append(&msgs, diet_tool("c2", "read_file", part))
	corvus_pad(&msgs, 4)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.corvus.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[4].content, CORVUS_STUB_PREFIX))
	testing.expect(t, strings.contains(d[4].content, "already delivered"))
	testing.expect(t, strings.contains(d[2].content, "l6"))
}

@(test)
test_corvus_partial_overlap_kept :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	first := corvus_read_result("/f", "l1", "l2", "l3", "l4")
	defer delete(first)
	second := corvus_read_result("/f", "l3", "l4", "l5", "l6")
	defer delete(second)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/f","offset":1,"limit":4}`)))
	append(&msgs, diet_tool("c1", "read_file", first))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/f","offset":3,"limit":4}`)))
	append(&msgs, diet_tool("c2", "read_file", second))
	corvus_pad(&msgs, 4)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	// Lines 5 and 6 are new delivery, so the second read stays whole.
	testing.expect_value(t, st.corvus.stubbed, 0)
	testing.expect(t, strings.contains(d[2].content, "l1"))
	testing.expect(t, strings.contains(d[4].content, "l6"))
}

@(test)
test_corvus_edit_invalidates_read :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	v1 := corvus_read_result("/f", "v1 body")
	defer delete(v1)
	v2 := corvus_read_result("/f", "v2 fresh")
	defer delete(v2)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/f"}`)))
	append(&msgs, diet_tool("c1", "read_file", v1))
	append(&msgs, diet_asst("", diet_call("e1", "edit_file", `{"path":"/f","old_string":"v1","new_string":"v2"}`)))
	append(&msgs, diet_tool("e1", "edit_file", "ok"))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/f"}`)))
	append(&msgs, diet_tool("c2", "read_file", v2))
	corvus_pad(&msgs, 4)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.corvus.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[2].content, CORVUS_STUB_PREFIX))
	testing.expect(t, strings.contains(d[2].content, "stale, see newer read"))
	testing.expect(t, strings.contains(d[6].content, "v2 fresh"))
	// The block reports the post-edit hash, not a modified marker.
	last := d[len(d) - 1].content
	testing.expect(t, strings.contains(last, CORVUS_STATE_MARK))
	testing.expect(t, !strings.contains(last, "/f modified"))
}

@(test)
test_corvus_state_block_modified :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	xv := corvus_read_result("/x", "old")
	defer delete(xv)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/x"}`)))
	append(&msgs, diet_tool("c1", "read_file", xv))
	append(&msgs, diet_asst("", diet_call("e1", "edit_file", `{"path":"/x","old_string":"old","new_string":"new"}`)))
	append(&msgs, diet_tool("e1", "edit_file", "ok"))
	corvus_pad(&msgs, 3)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	// No newer read survives, so the stale stub says the file changed.
	testing.expect(t, strings.has_prefix(d[2].content, CORVUS_STUB_PREFIX))
	testing.expect(t, strings.contains(d[2].content, "stale, file modified"))
	last := d[len(d) - 1].content
	testing.expect(t, strings.contains(last, CORVUS_STATE_MARK))
	testing.expect(t, strings.contains(last, "/x modified"))
	testing.expect(t, st.corvus.state_entries > 0)
}

@(test)
test_corvus_state_block_skip :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, diet_asst("hello"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.corvus.state_entries, 0)
	testing.expect_value(t, len(d), 0)
}

@(test)
test_corvus_disabled_env :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_CORVUS", "0")
	defer os.unset_env("NULLRAY_CORVUS")
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	body := corvus_read_result("/a", "alpha", "beta")
	defer delete(body)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/a"}`)))
	append(&msgs, diet_tool("c1", "read_file", body))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/a"}`)))
	append(&msgs, diet_tool("c2", "read_file", body))
	corvus_pad(&msgs, 4)
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.corvus.stubbed, 0)
	testing.expect_value(t, st.corvus.state_entries, 0)
	for m in d {
		testing.expect(t, !strings.contains(m.content, "corvus"))
	}
	// Plain diet still supersedes the older read.
	testing.expect(t, strings.has_prefix(d[2].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.contains(d[4].content, "alpha"))
}

@(test)
test_corvus_transcript_savings :: proc(t: ^testing.T) {
	fat_a := corvus_read_result("/a", strings.repeat("alpha line ", 60, context.temp_allocator))
	defer delete(fat_a)
	fat_b := corvus_read_result("/b", strings.repeat("beta line ", 60, context.temp_allocator))
	defer delete(fat_b)
	fat_c := corvus_read_result("/a", strings.repeat("gamma line ", 60, context.temp_allocator))
	defer delete(fat_c)
	listing := "one\nthree\ntwo"

	build := proc(fat_a, fat_b, fat_c, listing: string) -> [dynamic]provider.Message {
		msgs := make([dynamic]provider.Message)
		append(&msgs, provider.Message{role = .System, content = strings.clone("sys")})
		append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
		append(&msgs, diet_asst("", diet_call("r1", "read_file", `{"path":"/a"}`)))
		append(&msgs, diet_tool("r1", "read_file", fat_a))
		append(&msgs, diet_asst("", diet_call("r2", "read_file", `{"path":"/b"}`)))
		append(&msgs, diet_tool("r2", "read_file", fat_b))
		append(&msgs, diet_asst("", diet_call("r3", "read_file", `{"path":"/a"}`)))
		append(&msgs, diet_tool("r3", "read_file", fat_a))
		append(&msgs, diet_asst("", diet_call("w1", "edit_file", `{"path":"/a","old_string":"a","new_string":"g"}`)))
		append(&msgs, diet_tool("w1", "edit_file", "ok"))
		append(&msgs, diet_asst("", diet_call("r4", "read_file", `{"path":"/a"}`)))
		append(&msgs, diet_tool("r4", "read_file", fat_c))
		append(&msgs, diet_asst("", diet_call("l1", "list_dir", `{"path":"/d"}`)))
		append(&msgs, diet_tool("l1", "list_dir", listing))
		append(&msgs, diet_asst("", diet_call("l2", "list_dir", `{"path":"/d"}`)))
		append(&msgs, diet_tool("l2", "list_dir", listing))
		append(&msgs, diet_asst("", diet_call("r5", "read_file", `{"path":"/b"}`)))
		append(&msgs, diet_tool("r5", "read_file", fat_b))
		append(&msgs, diet_asst("", diet_call("s1", "run_shell", `{"command":"go"}`)))
		append(&msgs, diet_tool("s1", "run_shell", "shell out"))
		append(&msgs, diet_asst("done"))
		return msgs
	}

	msgs := build(fat_a, fat_b, fat_c, listing)
	defer diet_destroy(msgs)
	before := messages_content_chars(msgs[:])
	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)

	testing.expect(t, len(d) == len(msgs))
	testing.expect(t, st.chars_after < before)
	// Pre-edit /a reads go stale, the relist and /b reread dedup.
	testing.expect_value(t, st.corvus.stubbed, 4)
	testing.expect(t, strings.contains(d[3].content, "stale"))
	testing.expect(t, strings.contains(d[7].content, "stale"))
	testing.expect(t, strings.contains(d[15].content, "unchanged since msg 13"))
	testing.expect(t, strings.contains(d[17].content, "unchanged since msg 5"))
	testing.expect(t, strings.contains(d[len(d) - 1].content, CORVUS_STATE_MARK))
	testing.expect(t, diet_pairing_ok(d[:]))
	testing.expect(t, st.corvus.saved_chars > 0)

	// Same transcript through plain diet for a byte comparison.
	os.set_env("NULLRAY_CORVUS", "0")
	defer os.unset_env("NULLRAY_CORVUS")
	d2, st2 := diet_messages(msgs[:])
	defer diet_destroy(d2)
	testing.expect(t, st2.chars_after < before)
	testing.expect_value(t, st2.corvus.stubbed, 0)
	testing.expect(t, diet_pairing_ok(d2[:]))
	testing.expect(t, len(d2) == len(msgs))
}
