// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tests for extra skill path lists.
*/

package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "nullray:constants"

@(test)
test_split_skills_paths :: proc(t: ^testing.T) {
	parts := split_skills_paths("/a/skills,/b/skills", context.allocator)
	defer destroy_path_list(parts)
	testing.expect_value(t, len(parts), 2)
	testing.expect_value(t, parts[0], "/a/skills")
	testing.expect_value(t, parts[1], "/b/skills")

	empty := split_skills_paths("  ,  ", context.allocator)
	defer destroy_path_list(empty)
	testing.expect_value(t, len(empty), 0)
}

@(test)
test_extra_skills_path_loads :: proc(t: ^testing.T) {
	root := fmt.tprintf("/tmp/nullray-skill-extra-%d", os.get_pid())
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	extra, _ := filepath.join({root, "extra"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(extra) == nil)
	path, _ := filepath.join({extra, "fromenv.md"}, context.temp_allocator)
	body := "---\nname: fromenv\ndescription: via NULLRAY_SKILLS\n---\n\n# Env\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)body) == nil)

	os.set_env(constants.ENV_SKILLS, extra)
	defer os.unset_env(constants.ENV_SKILLS)
	os.set_env(constants.ENV_BARE, "1")
	defer os.unset_env(constants.ENV_BARE)

	loaded, _ := load_default()
	defer skills_destroy(&loaded)
	found := false
	for s in loaded {
		if s.id == "fromenv" {
			found = true
		}
	}
	testing.expect(t, found)
}
