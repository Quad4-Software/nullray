// SPDX-License-Identifier: 0BSD
/*
Copy a named scaffold template or pack into the workspace.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:sandbox"

scaffold_force_true :: proc(force: string) -> bool {
	fl := strings.to_lower(force, context.temp_allocator)
	return fl == "true" || fl == "1" || fl == "yes"
}

scaffold_copy_file :: proc(src, abs: string, allocator := context.allocator) -> string {
	if sandbox.path_is_secret_blocked(abs) {
		return strings.clone("secret path blocked", allocator)
	}
	if !sandbox.path_allowed(sandbox.state(), abs, true) {
		return strings.clone("path not allowed for write", allocator)
	}
	data, rerr := os.read_entire_file(src, context.temp_allocator)
	if rerr != nil {
		return fmt.aprintf("read scaffold failed: %v", rerr, allocator = allocator)
	}
	parent := filepath.dir(abs)
	_ = os.make_directory_all(parent)
	snapshot_before_write(abs)
	werr := os.write_entire_file(abs, data)
	if werr != nil {
		return fmt.aprintf("write scaffold failed: %v", werr, allocator = allocator)
	}
	return ""
}

scaffold_pack_entries :: proc(pack_dir: string, allocator := context.allocator) -> (
	entries: [dynamic]string,
	err: string,
) {
	entries = make([dynamic]string, allocator)
	manifest := fmt.tprintf("%s/MANIFEST.txt", pack_dir)
	data, rerr := os.read_entire_file(manifest, context.temp_allocator)
	if rerr != nil {
		return entries, fmt.aprintf("read MANIFEST failed: %v", rerr, allocator = allocator)
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		t := strings.trim_space(line)
		if len(t) == 0 || strings.has_prefix(t, "#") {
			continue
		}
		if strings.contains(t, "..") || strings.has_prefix(t, "/") {
			return entries, strings.clone("invalid MANIFEST path", allocator)
		}
		append(&entries, strings.clone(t, allocator))
	}
	if len(entries) == 0 {
		return entries, strings.clone("empty MANIFEST", allocator)
	}
	return entries, ""
}

tool_scaffold_pack :: proc(
	name, force: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	roots := scaffold_roots(context.temp_allocator)
	pack_dir := ""
	for root in roots {
		cand := scaffold_pack_dir(root, name, context.temp_allocator)
		if scaffold_is_pack(root, name) {
			pack_dir = cand
			break
		}
	}
	if len(pack_dir) == 0 {
		return "", fmt.aprintf("scaffold pack not found: %s", name, allocator = allocator)
	}
	entries, eerr := scaffold_pack_entries(pack_dir, context.temp_allocator)
	if len(eerr) > 0 {
		return "", eerr
	}
	force_ok := scaffold_force_true(force)
	abs_paths := make([dynamic]string, context.temp_allocator)
	src_paths := make([dynamic]string, context.temp_allocator)
	for rel in entries {
		src := fmt.tprintf("%s/%s", pack_dir, rel)
		if !os.exists(src) || os.is_dir(src) {
			return "", fmt.aprintf("pack missing file: %s", rel, allocator = allocator)
		}
		abs := resolve_path(rel, context.temp_allocator)
		if os.exists(abs) && !force_ok {
			return "", fmt.aprintf(
				"refusing overwrite (pass force=true): %s",
				abs,
				allocator = allocator,
			)
		}
		append(&abs_paths, abs)
		append(&src_paths, src)
	}
	for i in 0 ..< len(entries) {
		if cerr := scaffold_copy_file(src_paths[i], abs_paths[i], allocator); len(cerr) > 0 {
			return "", cerr
		}
	}
	warn := ""
	if force_ok {
		warn = " (force=true may overwrite)"
	}
	return fmt.aprintf(
		"scaffolded pack %s -> %d files%s",
		name,
		len(entries),
		warn,
		allocator = allocator,
	), ""
}

tool_scaffold :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	name, nerr := json_arg_string(args_json, "name", allocator)
	if nerr != "" {
		return "", nerr
	}
	defer delete(name)
	dest_rel, derr := json_arg_string_optional(args_json, "dest", "", allocator)
	if derr != "" {
		return "", derr
	}
	defer delete(dest_rel)
	force, ferr := json_arg_string_optional(args_json, "force", "false", allocator)
	if ferr != "" {
		return "", ferr
	}
	defer delete(force)

	n := strings.trim_space(name)
	if len(n) == 0 || strings.contains(n, "/") || strings.contains(n, "..") {
		return "", strings.clone("invalid scaffold name", allocator)
	}

	roots := scaffold_roots(context.temp_allocator)
	for root in roots {
		if scaffold_is_pack(root, n) {
			return tool_scaffold_pack(n, force, allocator)
		}
	}

	src := ""
	candidates := []string{n, fmt.tprintf("%s.yml", n), fmt.tprintf("%s.yaml", n), fmt.tprintf("%s.md", n)}
	for root in roots {
		for c in candidates {
			p := fmt.tprintf("%s/%s", root, c)
			if os.exists(p) && !os.is_dir(p) {
				src = p
				break
			}
		}
		if len(src) > 0 {
			break
		}
	}
	if len(src) == 0 {
		return "", fmt.aprintf("scaffold not found: %s", n, allocator = allocator)
	}

	out_name := filepath.base(src)
	if len(strings.trim_space(dest_rel)) > 0 {
		out_name = strings.trim_space(dest_rel)
	}
	abs := resolve_path(out_name, allocator)
	defer delete(abs)
	if os.exists(abs) && !scaffold_force_true(force) {
		return "", fmt.aprintf("refusing overwrite (pass force=true): %s", abs, allocator = allocator)
	}
	if cerr := scaffold_copy_file(src, abs, allocator); len(cerr) > 0 {
		return "", cerr
	}
	return fmt.aprintf("scaffolded %s -> %s", n, abs, allocator = allocator), ""
}
