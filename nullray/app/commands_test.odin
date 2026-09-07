// SPDX-License-Identifier: 0BSD
/*
Slash catalog registration for /skills.
*/

package app

import "core:strings"
import "core:testing"

@(test)
test_slash_skills_registered :: proc(t: ^testing.T) {
	cmd, ok := slash_find("skills")
	testing.expect(t, ok)
	testing.expect_value(t, cmd.usage, "/skills [ID]")
	testing.expect(t, cmd.run != nil)

	alias, aok := slash_find("skill")
	testing.expect(t, aok)
	testing.expect(t, alias.run == cmd.run)
}

@(test)
test_slash_arg_hint_shows_usage :: proc(t: ^testing.T) {
	hint := slash_arg_hint("/new")
	testing.expect(t, strings.contains(hint, "/new"))
	testing.expect(t, strings.contains(hint, "NAME") || strings.contains(hint, "name"))

	hint2 := slash_arg_hint("/resume ")
	testing.expect(t, strings.contains(hint2, "/resume NAME"))
}

@(test)
test_slash_complete_adds_space_for_args :: proc(t: ^testing.T) {
	done, ok := slash_complete("/ne", 0)
	testing.expect(t, ok)
	testing.expect(t, strings.has_prefix(done, "/new"))
	testing.expect(t, strings.has_suffix(done, " "))
}
