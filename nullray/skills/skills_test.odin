// SPDX-License-Identifier: 0BSD
/*
Tests for skill frontmatter, catalog, and matching.
*/

package skills

import "core:strings"
import "core:testing"

@(test)
test_split_frontmatter :: proc(t: ^testing.T) {
	meta, body := split_frontmatter("---\nname: foo\ndescription: bar\n---\n\n# Hello\n")
	testing.expect_value(t, meta, "name: foo\ndescription: bar")
	testing.expect(t, strings.has_prefix(body, "# Hello"))

	meta2, body2 := split_frontmatter("# no frontmatter\n")
	testing.expect_value(t, meta2, "")
	testing.expect_value(t, body2, "# no frontmatter\n")
}

@(test)
test_parse_frontmatter_folded_description :: proc(t: ^testing.T) {
	meta := "name: odin-idioms\ndescription: >\n  Odin package layout.\n  Use when editing .odin files.\n"
	name, desc := parse_frontmatter_fields(meta)
	defer delete(name)
	defer delete(desc)
	testing.expect_value(t, name, "odin-idioms")
	testing.expect(t, strings.contains(desc, "Odin package layout"))
	testing.expect(t, strings.contains(desc, "editing .odin"))
}

@(test)
test_render_catalog_no_bodies :: proc(t: ^testing.T) {
	sk := Skill{
		id = "memory",
		name = "memory",
		description = "Allocation ownership rules",
		body = "SECRET_BODY_SHOULD_NOT_APPEAR",
	}
	out := render_catalog([]Skill{sk})
	defer delete(out)
	testing.expect(t, strings.contains(out, "memory:"))
	testing.expect(t, strings.contains(out, "Allocation ownership"))
	testing.expect(t, !strings.contains(out, "SECRET_BODY"))
}

@(test)
test_match_skills_prefers_id_hit :: proc(t: ^testing.T) {
	sks := []Skill{
		{id = "prose", name = "prose", description = "docs and comments"},
		{id = "odin-idioms", name = "odin idioms", description = "Odin package layout and build tags"},
	}
	ids := match_skills(sks, "please edit nullray odin files using idioms")
	defer {
		for id in ids {
			delete(id)
		}
		delete(ids)
	}
	testing.expect(t, len(ids) >= 1)
	testing.expect_value(t, ids[0], "odin-idioms")
}

@(test)
test_skill_description_eval_precision :: proc(t: ^testing.T) {
	sks := []Skill{
		{
			id = "ci-pinned-actions",
			name = "ci pinned actions",
			description = "Pin GitHub Actions to commit SHAs. Use when editing .github/workflows.",
		},
		{
			id = "tui",
			name = "tui",
			description = "Terminal UI paint and input. Use when editing nullray/ui or app draw code.",
		},
	}
	should := match_skills(sks, "update the github workflow to pin actions")
	defer {
		for id in should {
			delete(id)
		}
		delete(should)
	}
	testing.expect(t, len(should) >= 1)
	testing.expect_value(t, should[0], "ci-pinned-actions")

	should_not := match_skills(sks, "what is the weather today")
	defer {
		for id in should_not {
			delete(id)
		}
		delete(should_not)
	}
	testing.expect_value(t, len(should_not), 0)
}

@(test)
test_format_list_text_empty :: proc(t: ^testing.T) {
	out := format_list_text({})
	defer delete(out)
	testing.expect_value(t, out, "(no skills)")
}

@(test)
test_format_list_text_sorted_with_source :: proc(t: ^testing.T) {
	sks := []Skill{
		{id = "tui", name = "tui", description = "paint cells", source = "/tmp/a"},
		{id = "prose", name = "prose", description = "docs style", source = "/tmp/b"},
	}
	out := format_list_text(sks)
	defer delete(out)
	testing.expect(t, strings.has_prefix(out, "prose: docs style  [/tmp/b]"))
	testing.expect(t, strings.contains(out, "\ntui: paint cells  [/tmp/a]"))
}

@(test)
test_format_detail_text_includes_body :: proc(t: ^testing.T) {
	sk := Skill{
		id = "memory",
		name = "memory",
		description = "ownership rules",
		body = "# Memory\nClone owned strings.\n",
		source = "/ws/.agents/skills",
		path = "/ws/.agents/skills/memory/SKILL.md",
	}
	out := format_detail_text(sk)
	defer delete(out)
	testing.expect(t, strings.contains(out, "id: memory\n"))
	testing.expect(t, strings.contains(out, "description: ownership rules\n"))
	testing.expect(t, strings.contains(out, "path: /ws/.agents/skills/memory/SKILL.md\n"))
	testing.expect(t, strings.contains(out, "# Memory\n"))
	testing.expect(t, strings.contains(out, "Clone owned strings.\n"))
}

@(test)
test_skills_show_text_unknown :: proc(t: ^testing.T) {
	text, ok := skills_show_text("__nullray_missing_skill_id__")
	testing.expect(t, !ok)
	testing.expect_value(t, text, "")
}
