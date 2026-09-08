// SPDX-License-Identifier: 0BSD
package patch

import "core:strings"
import "core:testing"

@(test)
test_exact_replace :: proc(t: ^testing.T) {
	updated, kind, err := apply_replace("alpha beta gamma", "beta", "BETA", false)
	defer delete(updated)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect_value(t, kind, Match_Kind.Exact)
	testing.expect_value(t, updated, "alpha BETA gamma")
}

@(test)
test_crlf_fuzzy :: proc(t: ^testing.T) {
	hay := "line one\r\nline two\r\nline three\r\n"
	old := "line one\nline two\n"
	updated, kind, err := apply_replace(hay, old, "LINE ONE\nLINE TWO\n", false)
	defer delete(updated)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect_value(t, kind, Match_Kind.Fuzzy)
	testing.expect(t, strings.contains(updated, "LINE ONE"))
	testing.expect(t, strings.contains(updated, "line three"))
}

@(test)
test_indent_fuzzy :: proc(t: ^testing.T) {
	hay := "fn main() {\n\treturn 1\n}\n"
	old := "fn main() {\n  return 1\n}"
	updated, kind, err := apply_replace(hay, old, "fn main() {\n\treturn 2\n}", false)
	defer delete(updated)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect(t, kind == .Exact || kind == .Fuzzy)
	testing.expect(t, strings.contains(updated, "return 2"))
}

@(test)
test_ambiguous_refuse :: proc(t: ^testing.T) {
	hay := "aaa\nbbb\nccc\naaa\nbbb\nddd\n"
	old := "aaa \nbbb\n"
	updated, kind, err := apply_replace(hay, old, "XXX\n", false)
	defer delete(updated)
	defer delete(err)
	testing.expect_value(t, kind, Match_Kind.Ambiguous)
	testing.expect(t, len(err) > 0)
}

@(test)
test_replace_all_exact :: proc(t: ^testing.T) {
	updated, kind, err := apply_replace("x y x", "x", "z", true)
	defer delete(updated)
	defer delete(err)
	testing.expect(t, len(err) == 0)
	testing.expect_value(t, kind, Match_Kind.Exact)
	testing.expect_value(t, updated, "z y z")
}

@(test)
test_empty_old_refuse :: proc(t: ^testing.T) {
	updated, kind, err := apply_replace("abc", "", "x", false)
	defer delete(updated)
	defer delete(err)
	testing.expect_value(t, kind, Match_Kind.None)
	testing.expect(t, len(err) > 0)
}

@(test)
test_hint_capped :: proc(t: ^testing.T) {
	h := format_hint("/tmp/foo.odin", "no match", "alpha\nbeta\n", "zzz")
	defer delete(h)
	testing.expect(t, len(h) <= HINT_MAX)
	testing.expect(t, strings.contains(h, "foo.odin"))
}
