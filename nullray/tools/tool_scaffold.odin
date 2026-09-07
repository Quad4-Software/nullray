// SPDX-License-Identifier: 0BSD
/*
Copy a named scaffold template into the workspace.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:sandbox"

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

	roots := make([dynamic]string, context.temp_allocator)
	if exe, eerr := os.get_executable_path(context.temp_allocator); eerr == nil {
		exe_dir := filepath.dir(exe)
		append(&roots, fmt.tprintf("%s/../share/nullray/scaffolds", exe_dir))
		append(&roots, fmt.tprintf("%s/share/nullray/scaffolds", exe_dir))
	}
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		append(&roots, fmt.tprintf("%s/share/nullray/scaffolds", st.workspace))
		append(&roots, fmt.tprintf("%s/.agents/skills/scaffold/references", st.workspace))
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
	if sandbox.path_is_secret_blocked(abs) {
		return "", strings.clone("secret path blocked", allocator)
	}
	if !sandbox.path_allowed(sandbox.state(), abs, true) {
		return "", strings.clone("path not allowed for write", allocator)
	}
	if os.exists(abs) {
		fl := strings.to_lower(force, context.temp_allocator)
		if fl != "true" && fl != "1" && fl != "yes" {
			return "", fmt.aprintf("refusing overwrite (pass force=true): %s", abs, allocator = allocator)
		}
	}

	data, rerr := os.read_entire_file(src, context.temp_allocator)
	if rerr != nil {
		return "", fmt.aprintf("read scaffold failed: %v", rerr, allocator = allocator)
	}
	parent := filepath.dir(abs)
	_ = os.make_directory_all(parent)
	snapshot_before_write(abs)
	werr := os.write_entire_file(abs, data)
	if werr != nil {
		return "", fmt.aprintf("write scaffold failed: %v", werr, allocator = allocator)
	}
	return fmt.aprintf("scaffolded %s -> %s", n, abs, allocator = allocator), ""
}
