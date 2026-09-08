// SPDX-License-Identifier: 0BSD
package tools

import "core:testing"

@(test)
test_speculate_allowlist_rejects_writes_and_specials :: proc(t: ^testing.T) {
	testing.expect(t, speculate_allowlisted("read_file"))
	testing.expect(t, speculate_allowlisted("grep_files"))
	testing.expect(t, !speculate_allowlisted("write_file"))
	testing.expect(t, !speculate_allowlisted("run_shell"))
	testing.expect(t, !speculate_allowlisted("compact_context"))
	testing.expect(t, !speculate_allowlisted("task"))
	testing.expect(t, !speculate_allowlisted("fetch_url"))
}

@(test)
test_speculate_leading_prefix :: proc(t: ^testing.T) {
	names := []string{"read_file", "list_dir", "write_file", "read_file"}
	testing.expect(t, speculate_leading_prefix_len(names) == 2)
	all_read := []string{"read_file", "grep_files"}
	testing.expect(t, speculate_leading_prefix_len(all_read) == 2)
}

@(test)
test_speculate_pool_hit_miss_cancel :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	pool: Speculate_Pool
	speculate_pool_init(&pool, &reg, "ask", 2)
	defer speculate_pool_destroy(&pool)

	args := `{}`
	ok := speculate_submit(&pool, "c1", "list_skills", args)
	testing.expect(t, ok)

	take := speculate_take(&pool, "c1", "list_skills", args)
	testing.expect(t, take.hit)
	testing.expect(t, take.ok)
	testing.expect(t, take.pre_ran)
	delete(take.result)
	delete(take.err)

	miss := speculate_take(&pool, "c1", "list_skills", `{"filter":"x"}`)
	testing.expect(t, !miss.hit)

	testing.expect(t, !speculate_submit(&pool, "c2", "write_file", `{"path":"x","content":"y"}`))

	speculate_discard_all(&pool)
	ok2 := speculate_submit(&pool, "c3", "list_dir", `{"path":"."}`)
	testing.expect(t, !ok2)
}

@(test)
test_speculate_args_hash_stable :: proc(t: ^testing.T) {
	a := speculate_args_hash(`{"path":"a"}`)
	b := speculate_args_hash(`{"path":"a"}`)
	c := speculate_args_hash(`{"path":"b"}`)
	testing.expect(t, a == b)
	testing.expect(t, a != c)
}
