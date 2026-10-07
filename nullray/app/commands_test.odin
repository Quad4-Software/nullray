// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash catalog registration for /skills.
*/

package app

import "core:strings"
import "core:testing"
import "nullray:provider"

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
test_slash_provider_registered :: proc(t: ^testing.T) {
	cmd, ok := slash_find("provider")
	testing.expect(t, ok)
	testing.expect_value(t, cmd.usage, "/provider [ID|next|prev|setup]")
	testing.expect(t, cmd.run != nil)

	list, lok := slash_find("providers")
	testing.expect(t, lok)
	testing.expect_value(t, list.usage, "/providers")
	testing.expect(t, list.run != nil)
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

@(test)
test_slash_provider_arg_complete :: proc(t: ^testing.T) {
	hint := slash_arg_hint("/provider ")
	testing.expect_value(t, hint, "")

	matches := slash_matches("/provider ope")
	testing.expect(t, len(matches) >= 2)

	done, ok := slash_complete("/provider openr", 0)
	testing.expect(t, ok)
	testing.expect_value(t, done, "/provider openrouter")

	next_done, next_ok := slash_complete("/provider ne", 0)
	testing.expect(t, next_ok)
	testing.expect_value(t, next_done, "/provider next")
}

@(test)
test_slash_model_arg_matches :: proc(t: ^testing.T) {
	p := provider.Provider{id = "test-prov", default_model = "cur-model"}
	provider.catalog_note_active(&p)
	provider.catalog_store("test-prov", []provider.Model_Info{{id = "alpha-1"}, {id = "zz-beta-2"}})
	defer provider.catalog_reset()

	hint := slash_arg_hint("/model ")
	testing.expect_value(t, hint, "")

	matches := model_slash_arg_matches("")
	testing.expect(t, len(matches) >= 3)
	testing.expect_value(t, matches[0].name, "cur-model")
	testing.expect_value(t, matches[0].help, "current model")

	sub := model_slash_arg_matches("beta")
	testing.expect_value(t, len(sub), 1)
	testing.expect_value(t, sub[0].name, "zz-beta-2")

	extras := model_slash_arg_matches("unl")
	testing.expect(t, len(extras) >= 1)
	testing.expect_value(t, extras[len(extras) - 1].name, "unlock")

	done, ok := slash_complete("/model a", 0)
	testing.expect(t, ok)
	testing.expect_value(t, done, "/model alpha-1")

	testing.expect_value(t, catalog_expand_unique("zz"), "zz-beta-2")
	testing.expect_value(t, catalog_expand_unique("alpha-1"), "alpha-1")
	testing.expect_value(t, catalog_expand_unique("beta"), "beta")
}
