// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_repo_map_extract_odin :: proc(t: ^testing.T) {
	src := "package x\nfoo :: proc() {}\nBar :: struct {}\n"
	syms := repo_map_extract_symbols("odin", src)
	testing.expect(t, len(syms) >= 2)
	joined := strings.join(syms, ",", context.temp_allocator)
	testing.expect(t, strings.contains(joined, "foo"))
	testing.expect(t, strings.contains(joined, "Bar"))
}

@(test)
test_repo_map_extract_go :: proc(t: ^testing.T) {
	src := "package p\nfunc Hello() {}\nfunc (t *T) Method() {}\ntype Box struct {}\n"
	syms := repo_map_extract_symbols("go", src)
	joined := strings.join(syms, ",", context.temp_allocator)
	testing.expect(t, strings.contains(joined, "Hello"))
	testing.expect(t, strings.contains(joined, "Method"))
	testing.expect(t, strings.contains(joined, "Box"))
}

@(test)
test_repo_map_extract_py_rs :: proc(t: ^testing.T) {
	py := repo_map_extract_symbols("py", "def run():\n    pass\nclass App:\n    pass\n")
	testing.expect(t, strings.contains(strings.join(py, ",", context.temp_allocator), "run"))
	rs := repo_map_extract_symbols("rs", "pub fn main() {}\nstruct Foo {}\n")
	testing.expect(t, strings.contains(strings.join(rs, ",", context.temp_allocator), "main"))
	testing.expect(t, strings.contains(strings.join(rs, ",", context.temp_allocator), "Foo"))
}
