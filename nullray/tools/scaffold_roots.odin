// SPDX-License-Identifier: 0BSD
/*
Shared scaffold root discovery for list and copy tools.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:sandbox"

scaffold_roots :: proc(allocator := context.allocator) -> [dynamic]string {
	roots := make([dynamic]string, allocator)
	if exe, eerr := os.get_executable_path(context.temp_allocator); eerr == nil {
		exe_dir := filepath.dir(exe)
		append(&roots, strings.clone(fmt.tprintf("%s/../share/nullray/scaffolds", exe_dir), allocator))
		append(&roots, strings.clone(fmt.tprintf("%s/share/nullray/scaffolds", exe_dir), allocator))
	}
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		append(&roots, strings.clone(fmt.tprintf("%s/share/nullray/scaffolds", st.workspace), allocator))
		append(
			&roots,
			strings.clone(fmt.tprintf("%s/.agents/skills/scaffold/references", st.workspace), allocator),
		)
	}
	if cwd, cerr := os.get_working_directory(context.temp_allocator); cerr == nil {
		append(&roots, strings.clone(fmt.tprintf("%s/share/nullray/scaffolds", cwd), allocator))
	}
	return roots
}

scaffold_roots_destroy :: proc(roots: ^[dynamic]string) {
	if roots == nil {
		return
	}
	for r in roots {
		delete(r)
	}
	delete(roots^)
	roots^ = {}
}

scaffold_pack_dir :: proc(root, name: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/packs/%s", root, name, allocator = allocator)
}

scaffold_is_pack :: proc(root, name: string) -> bool {
	dir := scaffold_pack_dir(root, name, context.temp_allocator)
	manifest := fmt.tprintf("%s/MANIFEST.txt", dir)
	return os.is_directory(dir) && os.exists(manifest)
}

tool_list_scaffolds :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	roots := scaffold_roots(context.temp_allocator)
	seen := make(map[string]bool, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	count := 0
	for root in roots {
		if !os.is_directory(root) {
			continue
		}
		packs := fmt.tprintf("%s/packs", root)
		if os.is_directory(packs) {
			if dh, herr := os.open(packs); herr == nil {
				defer os.close(dh)
				if infos, rerr := os.read_dir(dh, -1, context.temp_allocator); rerr == nil {
					for info in infos {
						if info.type != .Directory {
							continue
						}
						name := info.name
						if name == "." || name == ".." {
							continue
						}
						if !scaffold_is_pack(root, name) {
							continue
						}
						key := fmt.tprintf("pack:%s", name)
						if seen[key] {
							continue
						}
						seen[key] = true
						fmt.sbprintf(&b, "pack\t%s\tpacks/%s/\n", name, name)
						count += 1
					}
				}
			}
		}
		if dh, herr := os.open(root); herr == nil {
			defer os.close(dh)
			if infos, rerr := os.read_dir(dh, -1, context.temp_allocator); rerr == nil {
				for info in infos {
					if info.type == .Directory {
						continue
					}
					name := info.name
					if name == "versions.json" || name == "MANIFEST.txt" {
						continue
					}
					stem := name
					if strings.has_suffix(stem, ".yml") {
						stem = stem[:len(stem) - 4]
					} else if strings.has_suffix(stem, ".yaml") {
						stem = stem[:len(stem) - 5]
					} else if strings.has_suffix(stem, ".md") {
						stem = stem[:len(stem) - 3]
					}
					key := fmt.tprintf("file:%s", stem)
					if seen[key] {
						continue
					}
					seen[key] = true
					fmt.sbprintf(&b, "file\t%s\t%s\n", stem, name)
					count += 1
				}
			}
		}
	}
	if count == 0 {
		return strings.clone("no scaffolds found", allocator), ""
	}
	return strings.to_string(b), ""
}
