// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package skills

import "core:strings"
import "core:testing"

@(test)
test_parse_frontmatter_paths_list :: proc(t: ^testing.T) {
	meta := "name: odin\npaths:\n  - \"*.odin\"\n  - nullray/app/**\n"
	ps := parse_frontmatter_paths(meta)
	defer {
		for p in ps {
			delete(p)
		}
		delete(ps)
	}
	testing.expect_value(t, len(ps), 2)
	testing.expect_value(t, ps[0], "*.odin")
	testing.expect_value(t, ps[1], "nullray/app/**")
}

@(test)
test_parse_frontmatter_paths_inline :: proc(t: ^testing.T) {
	meta := `paths: ["*.go", "cmd/**"]`
	ps := parse_frontmatter_paths(meta)
	defer {
		for p in ps {
			delete(p)
		}
		delete(ps)
	}
	testing.expect_value(t, len(ps), 2)
	testing.expect_value(t, ps[0], "*.go")
}

@(test)
test_skill_path_matches :: proc(t: ^testing.T) {
	testing.expect(t, skill_path_matches("*.odin", "foo.odin"))
	testing.expect(t, skill_path_matches("*.odin", "nullray/app/x.odin"))
	testing.expect(t, skill_path_matches("nullray/app/**", "nullray/app/input.odin"))
	testing.expect(t, !skill_path_matches("*.go", "foo.odin"))
}
