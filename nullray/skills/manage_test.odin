// SPDX-License-Identifier: 0BSD
/*
Tests for skill install, uninstall, and path list parsing.
*/

package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
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
test_sanitize_skill_id :: proc(t: ^testing.T) {
	a := sanitize_skill_id("prose")
	defer delete(a)
	testing.expect_value(t, a, "prose")
	b := sanitize_skill_id("../weird name")
	defer delete(b)
	testing.expect_value(t, b, "___weird_name")
}

@(test)
test_install_uninstall_flat_skill :: proc(t: ^testing.T) {
	root := fmt.tprintf("/tmp/nullray-skill-test-%d", os.get_pid())
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	src_dir, _ := filepath.join({root, "src"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(src_dir) == nil)

	src, _ := filepath.join({src_dir, "demo.md"}, context.temp_allocator)
	body := "---\nname: demo\ndescription: install test skill\n---\n\n# Demo\n"
	testing.expect(t, os.write_entire_file(src, transmute([]byte)body) == nil)

	os.set_env("XDG_CONFIG_HOME", root)
	defer os.unset_env("XDG_CONFIG_HOME")
	// resolve_config_dir may use XDG or HOME/nullray. Force via HOME-less XDG.
	// default_skills_dir uses sandbox.resolve_config_dir which honors XDG_CONFIG_HOME/nullray.
	cfg_nullray, _ := filepath.join({root, "nullray"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cfg_nullray) == nil)

	id, dest, err := install_skill(src)
	testing.expect_value(t, err, "")
	testing.expect_value(t, id, "demo")
	testing.expect(t, os.exists(dest))
	defer delete(id)
	defer delete(dest)

	loaded, _ := load_dir(filepath.dir(dest))
	defer skills_destroy(&loaded)
	testing.expect(t, len(loaded) >= 1)
	found := false
	for s in loaded {
		if s.id == "demo" {
			found = true
			testing.expect(t, strings.contains(s.description, "install test"))
		}
	}
	testing.expect(t, found)

	ok, uerr := uninstall_skill("demo")
	testing.expect(t, ok)
	testing.expect_value(t, uerr, "")
	testing.expect(t, !os.exists(dest))
}

@(test)
test_install_package_skill :: proc(t: ^testing.T) {
	root := fmt.tprintf("/tmp/nullray-skill-pkg-%d", os.get_pid())
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	os.set_env("XDG_CONFIG_HOME", root)
	defer os.unset_env("XDG_CONFIG_HOME")
	cfg_nullray, _ := filepath.join({root, "nullray"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cfg_nullray) == nil)

	pkg, _ := filepath.join({root, "src", "pack"}, context.temp_allocator)
	refs, _ := filepath.join({pkg, "references"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(refs) == nil)
	skill_md, _ := filepath.join({pkg, "SKILL.md"}, context.temp_allocator)
	ref_md, _ := filepath.join({refs, "notes.md"}, context.temp_allocator)
	body := "---\nname: pack\ndescription: package skill\n---\n\n# Pack\n"
	testing.expect(t, os.write_entire_file(skill_md, transmute([]byte)body) == nil)
	testing.expect(t, os.write_entire_file(ref_md, "note\n") == nil)

	id, dest, err := install_skill(pkg, "renamed")
	testing.expect_value(t, err, "")
	testing.expect_value(t, id, "renamed")
	defer delete(id)
	defer delete(dest)
	copied_ref, _ := filepath.join({dest, "references", "notes.md"}, context.temp_allocator)
	testing.expect(t, os.exists(copied_ref))

	ok, uerr := uninstall_skill("renamed")
	testing.expect(t, ok)
	testing.expect_value(t, uerr, "")
	testing.expect(t, !os.exists(dest))
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
