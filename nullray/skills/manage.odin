// SPDX-License-Identifier: 0BSD
/*
Install and uninstall skills under the config skills dir.
Extra search roots from NULLRAY_SKILLS and --skills.
*/

package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

/*
Split comma and OS path-list separators into trimmed paths.
Caller owns the returned slice strings when allocator is not temp.
*/
split_skills_paths :: proc(raw: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, 0, 4, allocator)
	if len(strings.trim_space(raw)) == 0 {
		return out[:]
	}
	start := 0
	for i := 0; i <= len(raw); i += 1 {
		at_end := i == len(raw)
		sep := false
		if !at_end {
			c := raw[i]
			if c == ',' || c == u8(filepath.LIST_SEPARATOR) {
				sep = true
			}
		} else {
			sep = true
		}
		if !sep {
			continue
		}
		part := strings.trim_space(raw[start:i])
		if len(part) > 0 {
			append(&out, strings.clone(part, allocator))
		}
		start = i + 1
	}
	return out[:]
}

skills_paths_from_env :: proc(allocator := context.allocator) -> []string {
	raw, ok := os.lookup_env(constants.ENV_SKILLS, context.temp_allocator)
	if !ok || len(strings.trim_space(raw)) == 0 {
		return {}
	}
	return split_skills_paths(raw, allocator)
}

destroy_path_list :: proc(paths: []string, allocator := context.allocator) {
	for p in paths {
		delete(p, allocator)
	}
	delete(paths, allocator)
}

sanitize_skill_id :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for r in s {
		switch r {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
			strings.write_rune(&b, r)
		case:
			strings.write_rune(&b, '_')
		}
	}
	out := strings.to_string(b)
	if len(out) == 0 {
		return strings.clone("skill", allocator)
	}
	return strings.clone(out, allocator)
}

resolve_skill_src :: proc(path: string, allocator := context.allocator) -> string {
	clean, cerr := filepath.clean(path, context.temp_allocator)
	if cerr != nil {
		clean = path
	}
	if filepath.is_abs(clean) {
		return strings.clone(clean, allocator)
	}
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return strings.clone(clean, allocator)
	}
	joined, jerr := filepath.join({cwd, clean}, allocator)
	if jerr != nil {
		return strings.clone(clean, allocator)
	}
	return joined
}

@(private)
copy_file_bytes :: proc(src, dst: string) -> bool {
	data, err := os.read_entire_file(src, context.temp_allocator)
	if err != nil {
		return false
	}
	return os.write_entire_file(dst, data) == nil
}

@(private)
copy_tree :: proc(src, dst: string) -> string {
	info, err := os.stat(src, context.temp_allocator)
	if err != nil {
		return fmt.tprintf("stat failed: %s", src)
	}
	if info.type == .Regular {
		dir := filepath.dir(dst)
		_ = os.make_directory_all(dir)
		if !copy_file_bytes(src, dst) {
			return fmt.tprintf("copy failed: %s -> %s", src, dst)
		}
		return ""
	}
	if info.type != .Directory {
		return fmt.tprintf("unsupported path type: %s", src)
	}
	if mkerr := os.make_directory_all(dst); mkerr != nil {
		if st, serr := os.stat(dst, context.temp_allocator); serr != nil || st.type != .Directory {
			return fmt.tprintf("cannot create directory %s", dst)
		}
	}
	entries, rerr := os.read_all_directory_by_path(src, context.temp_allocator)
	if rerr != nil {
		return fmt.tprintf("read dir failed: %s", src)
	}
	for e in entries {
		if e.name == "." || e.name == ".." {
			continue
		}
		child_src, serr := filepath.join({src, e.name}, context.temp_allocator)
		if serr != nil {
			continue
		}
		child_dst, derr := filepath.join({dst, e.name}, context.temp_allocator)
		if derr != nil {
			continue
		}
		if msg := copy_tree(child_src, child_dst); len(msg) > 0 {
			return msg
		}
	}
	return ""
}

/*
Install a skill file (.md) or package dir (SKILL.md) into ~/.config/nullray/skills.
as_id overrides the destination id when non-empty.
Returns owned id and dest path. Caller deletes them on success.
*/
install_skill :: proc(
	src_path: string,
	as_id := "",
	allocator := context.allocator,
) -> (id: string, dest: string, err: string) {
	src := resolve_skill_src(src_path, context.temp_allocator)
	info, serr := os.stat(src, context.temp_allocator)
	if serr != nil {
		return "", "", fmt.aprintf("skill source not found: %s", src_path, allocator = allocator)
	}

	want_id := strings.trim_space(as_id)
	is_pkg := false
	src_file := src

	if info.type == .Directory {
		skill_md, jerr := filepath.join({src, "SKILL.md"}, context.temp_allocator)
		if jerr != nil {
			skill_md = fmt.tprintf("%s/SKILL.md", src)
		}
		if !os.exists(skill_md) {
			return "", "", fmt.aprintf(
				"directory needs SKILL.md (got %s)",
				src_path,
				allocator = allocator,
			)
		}
		is_pkg = true
		if len(want_id) == 0 {
			want_id = filepath.base(src)
		}
	} else if info.type == .Regular {
		if !strings.has_suffix(strings.to_lower(src, context.temp_allocator), ".md") {
			return "", "", fmt.aprintf("skill file must be .md: %s", src_path, allocator = allocator)
		}
		if len(want_id) == 0 {
			base := filepath.base(src)
			if strings.has_suffix(strings.to_lower(base, context.temp_allocator), ".md") {
				base = base[:len(base) - 3]
			}
			want_id = base
		}
	} else {
		return "", "", fmt.aprintf("unsupported skill source: %s", src_path, allocator = allocator)
	}

	id = sanitize_skill_id(want_id, allocator)
	if id == "skill" && len(strings.trim_space(want_id)) == 0 {
		delete(id)
		return "", "", strings.clone("skill id is empty", allocator)
	}

	root := default_skills_dir(context.temp_allocator)
	_ = os.make_directory_all(root)

	if is_pkg {
		dest_path, jerr := filepath.join({root, id}, allocator)
		if jerr != nil {
			dest_path = fmt.aprintf("%s/%s", root, id, allocator = allocator)
		}
		if os.exists(dest_path) {
			msg := fmt.aprintf("skill already installed: %s (uninstall first)", id, allocator = allocator)
			delete(id)
			delete(dest_path)
			return "", "", msg
		}
		if msg := copy_tree(src, dest_path); len(msg) > 0 {
			_ = os.remove_all(dest_path)
			delete(id)
			delete(dest_path)
			return "", "", strings.clone(msg, allocator)
		}
		return id, dest_path, ""
	}

	dest_path, jerr := filepath.join({root, fmt.tprintf("%s.md", id)}, allocator)
	if jerr != nil {
		dest_path = fmt.aprintf("%s/%s.md", root, id, allocator = allocator)
	}
	if os.exists(dest_path) {
		msg := fmt.aprintf("skill already installed: %s (uninstall first)", id, allocator = allocator)
		delete(id)
		delete(dest_path)
		return "", "", msg
	}
	dir := filepath.dir(dest_path)
	_ = os.make_directory_all(dir)
	if !copy_file_bytes(src_file, dest_path) {
		delete(id)
		delete(dest_path)
		return "", "", fmt.aprintf("failed to copy %s", src_path, allocator = allocator)
	}
	return id, dest_path, ""
}

/*
Remove a skill installed under the config skills directory only.
*/
uninstall_skill :: proc(skill_id: string, allocator := context.allocator) -> (ok: bool, err: string) {
	id := sanitize_skill_id(strings.trim_space(skill_id), context.temp_allocator)
	if len(id) == 0 || id == "skill" && len(strings.trim_space(skill_id)) == 0 {
		return false, strings.clone("uninstall needs a skill id", allocator)
	}
	root := default_skills_dir(context.temp_allocator)
	pkg, perr := filepath.join({root, id}, context.temp_allocator)
	if perr != nil {
		pkg = fmt.tprintf("%s/%s", root, id)
	}
	flat, ferr := filepath.join({root, fmt.tprintf("%s.md", id)}, context.temp_allocator)
	if ferr != nil {
		flat = fmt.tprintf("%s/%s.md", root, id)
	}

	removed := false
	if info, err := os.stat(pkg, context.temp_allocator); err == nil && info.type == .Directory {
		if os.remove_all(pkg) != nil {
			return false, fmt.aprintf("failed to remove %s", pkg, allocator = allocator)
		}
		removed = true
	}
	if os.exists(flat) {
		if os.remove(flat) != nil {
			return false, fmt.aprintf("failed to remove %s", flat, allocator = allocator)
		}
		removed = true
	}
	if !removed {
		return false, fmt.aprintf(
			"skill %s not installed under %s (workspace skills are not removed by uninstall)",
			id,
			root,
			allocator = allocator,
		)
	}
	return true, ""
}
