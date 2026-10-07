// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
g_stash_test_n: int

// Big enough to trip the default 800 char stash threshold, first line
// carries the call counter so LRU and take checks can tell bodies apart.
@(private)
stash_test_big :: proc(args: string, allocator := context.allocator) -> (string, string) {
	g_stash_test_n += 1
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "call=%d\n", g_stash_test_n)
	for i in 0 ..< 100 {
		fmt.sbprintf(&b, "row-%03d alpha beta gamma delta\n", i)
	}
	return strings.to_string(b), ""
}

@(private)
stash_test_small :: proc(args: string, allocator := context.allocator) -> (string, string) {
	return strings.clone("tiny ok", allocator), ""
}

@(private)
stash_test_registry :: proc(reg: ^Registry) {
	registry_init(reg)
	registry_register(reg, Tool{name = "bigtool", kind = .Read, run = stash_test_big})
	registry_register(reg, Tool{name = "smalltool", kind = .Read, run = stash_test_small})
	g_stash_test_n = 0
}

@(test)
test_stash_auto_replaces_body :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	res, err := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.has_prefix(res, "stashed as stash-1,"))
	testing.expect(t, strings.contains(res, "3107 bytes"))
	testing.expect(t, strings.contains(res, "preview"))
	// Head preview keeps the first 120 chars, the tail stays in the store.
	testing.expect(t, strings.contains(res, "call=1"))
	testing.expect(t, strings.contains(res, "row-000"))
	testing.expect(t, !strings.contains(res, "row-050"))
	testing.expect(t, len(res) < 400)

	n, ok := stash_saved_bytes(res)
	testing.expect(t, ok)
	testing.expect_value(t, n, 3107)
}

@(test)
test_stash_peek_returns_slice :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	res, err := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect_value(t, err, "")

	out, perr := run(&reg, "peek", `{"id":"stash-1","offset":"3","limit":"2"}`, "edit", context.allocator)
	defer delete(out)
	defer delete(perr)
	testing.expect_value(t, perr, "")
	testing.expect(t, strings.contains(out, "stash=stash-1"))
	testing.expect(t, strings.contains(out, "lines=3..4 of"))
	testing.expect(t, strings.contains(out, "row-001"))
	testing.expect(t, strings.contains(out, "row-002"))
	testing.expect(t, !strings.contains(out, "row-003"))
}

@(test)
test_stash_list_shape :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	res1, _ := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res1)
	res2, _ := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res2)

	out, lerr := run(&reg, "stash_list", `{}`, "edit", context.allocator)
	defer delete(out)
	defer delete(lerr)
	testing.expect_value(t, lerr, "")
	testing.expect(t, strings.contains(out, "stash-1 "))
	testing.expect(t, strings.contains(out, "stash-2 "))
	testing.expect(t, strings.contains(out, "bytes"))
	// One-line preview comes from the first body line.
	testing.expect(t, strings.contains(out, "call=1"))
	testing.expect(t, strings.contains(out, "call=2"))
}

@(test)
test_stash_take_recent_and_by_id :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	res1, _ := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res1)
	res2, _ := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res2)

	// No id: most recent stash.
	out, terr := run(&reg, "stash_take", `{}`, "edit", context.allocator)
	defer delete(out)
	defer delete(terr)
	testing.expect_value(t, terr, "")
	testing.expect(t, strings.contains(out, "stash=stash-2"))
	testing.expect(t, strings.contains(out, "call=2"))
	testing.expect(t, strings.contains(out, "row-099"))

	out2, terr2 := run(&reg, "stash_take", `{"id":"stash-1"}`, "edit", context.allocator)
	defer delete(out2)
	defer delete(terr2)
	testing.expect_value(t, terr2, "")
	testing.expect(t, strings.contains(out2, "stash=stash-1"))
	testing.expect(t, strings.contains(out2, "call=1"))

	_, terr3 := run(&reg, "stash_take", `{"id":"stash-99"}`, "edit", context.allocator)
	defer delete(terr3)
	testing.expect(t, strings.contains(terr3, "unknown stash id"))
}

@(test)
test_stash_lru_cap :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	for _ in 0 ..< 70 {
		res, _ := run(&reg, "bigtool", `{}`, "edit", context.allocator)
		delete(res)
	}
	out, lerr := run(&reg, "stash_list", `{}`, "edit", context.allocator)
	defer delete(out)
	defer delete(lerr)
	testing.expect_value(t, lerr, "")
	count := 0
	rest := out
	for {
		idx := strings.index(rest, "stash-")
		if idx < 0 {
			break
		}
		count += 1
		rest = rest[idx + 1:]
	}
	testing.expect_value(t, count, STASH_MAX_ENTRIES)
	testing.expect(t, strings.contains(out, "stash-70 "))
	testing.expect(t, strings.contains(out, "stash-7 "))
	testing.expect(t, !strings.contains(out, "stash-6 "))
	testing.expect(t, !strings.contains(out, "stash-1 "))

	_, terr := run(&reg, "peek", `{"id":"stash-1"}`, "edit", context.allocator)
	defer delete(terr)
	testing.expect(t, strings.contains(terr, "unknown stash id"))
}

@(test)
test_stash_disabled_env :: proc(t: ^testing.T) {
	os.set_env(ENV_STASH, "0")
	defer os.unset_env(ENV_STASH)

	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	res, err := run(&reg, "bigtool", `{}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(res, "row-099"))
	testing.expect(t, len(res) > 3000)

	out, _ := run(&reg, "stash_list", `{}`, "edit", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "no stashed results"))
}

@(test)
test_stash_small_result_and_err_unchanged :: proc(t: ^testing.T) {
	reg: Registry
	stash_test_registry(&reg)
	defer registry_destroy(&reg)

	// Small results pass through verbatim: result string and (result, err)
	// pairing are untouched by the scratchpad.
	res, err := run(&reg, "smalltool", `{}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect_value(t, res, "tiny ok")

	_, perr := run(&reg, "peek", `{}`, "edit", context.allocator)
	defer delete(perr)
	testing.expect(t, len(perr) > 0)
}
