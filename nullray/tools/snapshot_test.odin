// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tests for workspace checkpoints: batch grouping, shadow dedupe, restore,
keep pruning, and the NULLRAY_CHECKPOINT_AUTO gate.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:testing"
import "nullray:constants"
import "nullray:sandbox"

@(private)
snap_test_env_set :: proc(key, value: string) -> (had: bool, prev: string) {
	if v, ok := os.lookup_env(key, context.allocator); ok {
		had = true
		prev = v
	}
	os.set_env(key, value)
	return
}

@(private)
snap_test_env_restore :: proc(key: string, had: bool, prev: string) {
	if had {
		os.set_env(key, prev)
		delete(prev)
	} else {
		os.unset_env(key)
	}
}

@(private)
snap_test_ws :: proc(root: string) -> (prev: string) {
	prev = strings.clone(sandbox.workspace_current(), context.allocator)
	sandbox.workspace_override_set(root)
	return
}

@(private)
snap_test_ws_restore :: proc(prev: string) {
	if len(prev) > 0 {
		sandbox.workspace_override_set(prev)
	} else {
		sandbox.workspace_override_clear()
	}
	delete(prev)
}

@(private)
snap_test_dir_bytes :: proc(dir: string) -> i64 {
	total: i64 = 0
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return 0
	}
	for e in entries {
		if e.type == .Directory {
			total += snap_test_dir_bytes(e.fullpath)
		} else {
			total += e.size
		}
	}
	return total
}

@(private)
snap_test_count :: proc() -> int {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	return len(g_snaps)
}

@(test)
test_snapshot_write_modify_restore :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-roundtrip"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	abs, jerr := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("v1\n")) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	snapshot_before_write(abs)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("v2\n")) == nil)
	checkpoint_commit_step(1)

	snapshot_before_write(abs)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("v3\n")) == nil)
	checkpoint_commit_step(2)

	lst := checkpoint_list()
	defer delete(lst)
	testing.expect(t, strings.contains(lst, "step 2 - 1 files"))
	testing.expect(t, strings.contains(lst, "shadow"))

	// Restoring checkpoint 2 puts back the bytes recorded before that write.
	msg, ok := checkpoint_restore(2)
	defer delete(msg)
	testing.expect(t, ok)
	data, rerr := os.read_entire_file(abs, context.temp_allocator)
	testing.expect(t, rerr == nil)
	testing.expect_value(t, string(data), "v2\n")

	// Restoring checkpoint 1 puts back the original bytes.
	msg1, ok1 := checkpoint_restore(1)
	defer delete(msg1)
	testing.expect(t, ok1)
	data1, rerr1 := os.read_entire_file(abs, context.temp_allocator)
	testing.expect(t, rerr1 == nil)
	testing.expect_value(t, string(data1), "v1\n")
}

@(test)
test_snapshot_shadow_dedupes_same_bytes :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-dedup"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	abs, jerr := filepath.join({root, "big.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)

	big: strings.Builder
	strings.builder_init(&big, context.temp_allocator)
	for i in 0 ..< 1000 {
		fmt.sbprintf(&big, "line %d of repeated checkpoint payload\n", i)
	}
	payload := strings.to_string(big)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)payload) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	dir := snapshot_dir(context.temp_allocator)

	snapshot_before_write(abs)
	checkpoint_commit_step(1)
	size1 := snap_test_dir_bytes(dir)
	testing.expect(t, size1 > 0)

	// Snapshot the same unchanged bytes again. Blob dedupe means the shadow
	// repo grows only by commit, tree, and ref records, not the payload.
	snapshot_before_write(abs)
	checkpoint_commit_step(2)
	size2 := snap_test_dir_bytes(dir)
	testing.expectf(t, size2 - size1 < 16 * 1024, "shadow grew %d bytes for an unchanged file (size1=%d size2=%d)", size2 - size1, size1, size2)
	testing.expectf(t, size2 < i64(len(payload)), "shadow (%d) should stay under one payload copy (%d)", size2, len(payload))
}

@(test)
test_snapshot_created_file_removed_on_restore :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-created"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	abs, jerr := filepath.join({root, "new.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, !os.exists(abs))

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	snapshot_before_write(abs)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("made by agent\n")) == nil)
	checkpoint_commit_step(1)
	testing.expect(t, os.exists(abs))

	msg, ok := checkpoint_restore(1)
	defer delete(msg)
	testing.expect(t, ok)
	testing.expectf(t, !os.exists(abs), "created file still present after restore: %s", msg)
}

@(test)
test_snapshot_batch_groups_files_and_restores_all :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-batch"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	a, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	b, _ := filepath.join({root, "b.txt"}, context.temp_allocator)
	c, _ := filepath.join({root, "c.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(a, transmute([]u8)string("a1")) == nil)
	testing.expect(t, os.write_entire_file(b, transmute([]u8)string("b1")) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	// One step touches three files: two edits and one create.
	snapshot_before_write(a)
	snapshot_before_write(b)
	snapshot_before_write(c)
	testing.expect(t, os.write_entire_file(a, transmute([]u8)string("a2")) == nil)
	testing.expect(t, os.write_entire_file(b, transmute([]u8)string("b2")) == nil)
	testing.expect(t, os.write_entire_file(c, transmute([]u8)string("c1")) == nil)
	checkpoint_commit_step(3)

	lst := checkpoint_list()
	defer delete(lst)
	testing.expect(t, strings.contains(lst, "step 3 - 3 files"))

	msg, ok := checkpoint_restore(1)
	defer delete(msg)
	testing.expect(t, ok)

	da, _ := os.read_entire_file(a, context.temp_allocator)
	db, _ := os.read_entire_file(b, context.temp_allocator)
	testing.expect_value(t, string(da), "a1")
	testing.expect_value(t, string(db), "b1")
	testing.expect(t, !os.exists(c))
}

@(test)
test_snapshot_keep_prunes_oldest :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-keep"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	had, prev_env := snap_test_env_set(constants.ENV_CHECKPOINT_KEEP, "2")
	defer snap_test_env_restore(constants.ENV_CHECKPOINT_KEEP, had, prev_env)

	abs, jerr := filepath.join({root, "f.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("base")) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	for i in 0 ..< 5 {
		snapshot_before_write(abs)
		testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("rev")) == nil)
		checkpoint_commit_step(i + 1)
	}
	testing.expectf(t, snap_test_count() <= 2, "keep=2 but %d checkpoints retained", snap_test_count())

	lst := checkpoint_list()
	defer delete(lst)
	testing.expect(t, strings.contains(lst, "step 5"))
	testing.expect(t, !strings.contains(lst, "step 1"))
}

@(test)
test_snapshot_auto_disabled_records_nothing :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-auto-off"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	had, prev_env := snap_test_env_set(constants.ENV_CHECKPOINT_AUTO, "0")
	defer snap_test_env_restore(constants.ENV_CHECKPOINT_AUTO, had, prev_env)

	abs, jerr := filepath.join({root, "f.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("base")) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	snapshot_before_write(abs)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("changed")) == nil)
	checkpoint_commit_step(1)

	testing.expect_value(t, snap_test_count(), 0)
	lst := checkpoint_list()
	defer delete(lst)
	testing.expect(t, strings.contains(lst, "no checkpoints"))
}

@(test)
test_snapshot_skips_nullray_paths :: proc(t: ^testing.T) {
	root := "/tmp/nullray-snap-skip"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	inner, jerr := filepath.join({root, ".nullray", "artifacts"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.make_directory_all(inner) == nil)
	abs, jerr2 := filepath.join({inner, "dump.bin"}, context.temp_allocator)
	testing.expect(t, jerr2 == nil)
	testing.expect(t, os.write_entire_file(abs, transmute([]u8)string("noise")) == nil)

	prev := snap_test_ws(root)
	defer snap_test_ws_restore(prev)
	snapshots_destroy()
	defer snapshots_destroy()

	snapshot_before_write(abs)
	checkpoint_commit_step(1)
	testing.expect_value(t, snap_test_count(), 0)
}
