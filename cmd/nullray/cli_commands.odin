// SPDX-License-Identifier: 0BSD
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:http"
import "nullray:provider"
import "nullray:secure"
import "nullray:session"
import "nullray:skills"
import "nullray:store"

run_list_models :: proc() -> int {
	if !http.global_init() {
		fmt.eprintln("nullray: TLS init failed")
		return 1
	}
	defer http.global_cleanup()

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	p := provider.registry_active(&reg)
	if p == nil || p.list_models == nil {
		fmt.eprintln("nullray: no provider with list_models")
		return 1
	}
	fmt.printf("%s (%s) models via %s\n", p.name, p.id, p.base_url)
	models, err := p.list_models(p)
	if len(err) > 0 {
		fmt.eprintln("nullray: list-models:", err)
		return 1
	}
	defer provider.destroy_models(models)
	if len(models) == 0 {
		fmt.println("(none)")
		return 0
	}
	for m in models {
		fmt.println(m.id)
	}
	return 0
}

run_list_sessions :: proc() -> int {
	text := session.session_list_text()
	defer delete(text)
	fmt.println(text)
	return 0
}

run_inspect_session :: proc(cli: ^Cli) -> int {
	name := cli.inspect_session
	if len(name) == 0 && len(cli.session) > 0 {
		name = cli.session
	}
	path := session.resolve_inspect_path(name, context.temp_allocator)
	if cli.inspect_follow {
		return session.session_inspect_follow(path)
	}
	text := session.session_inspect_text(path, context.temp_allocator)
	fmt.println(text)
	return 0
}

run_search_sessions :: proc(query: string) -> int {
	text := session.session_search_text(query)
	defer delete(text)
	fmt.println(text)
	return 0
}

run_delete_session :: proc(name: string) -> int {
	ok, err := store.delete_session(name)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("deleted session %s\n", store.sanitize_name(name))
	return 0
}

run_rename_session :: proc(old_name, new_name: string, force: bool) -> int {
	if len(strings.trim_space(new_name)) == 0 {
		fmt.eprintln("nullray: --rename-session needs --as NEW")
		return 2
	}
	ok, err := store.rename_session_files(old_name, new_name, force)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("renamed session %s -> %s\n", store.sanitize_name(old_name), store.sanitize_name(new_name))
	return 0
}

run_export_session :: proc(name: string, out_dir: string) -> int {
	if len(strings.trim_space(out_dir)) == 0 {
		fmt.eprintln("nullray: --export-session needs --out DIR")
		return 2
	}
	ok, err := store.export_session(name, out_dir)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("exported session %s to %s\n", store.sanitize_name(name), out_dir)
	return 0
}

run_import_session :: proc(src: string, as_name: string) -> int {
	name, ok, err := store.import_session(src, as_name)
	if !ok {
		fmt.eprintln("nullray:", err)
		return 1
	}
	fmt.printf("imported session %s\n", name)
	fmt.printf("To resume this session: nullray --session %s\n", name)
	return 0
}

run_list_skills :: proc() -> int {
	text := skills.skills_list_text()
	defer delete(text)
	fmt.println(text)
	return 0
}

run_install_skill :: proc(src: string, as_name: string) -> int {
	id, dest, err := skills.install_skill(src, as_name)
	if len(err) > 0 {
		fmt.eprintln("nullray:", err)
		delete(err)
		return 1
	}
	defer delete(id)
	defer delete(dest)
	fmt.printf("installed skill %s -> %s\n", id, dest)
	return 0
}

run_uninstall_skill :: proc(id: string) -> int {
	ok, err := skills.uninstall_skill(id)
	if !ok {
		fmt.eprintln("nullray:", err)
		delete(err)
		return 1
	}
	fmt.printf("uninstalled skill %s\n", skills.sanitize_skill_id(id, context.temp_allocator))
	return 0
}

run_audit :: proc() -> int {
	root := env_or(constants.ENV_WORKSPACE, "")
	if len(root) == 0 {
		cwd, err := os.get_working_directory(context.temp_allocator)
		if err != nil {
			fmt.eprintln("nullray: audit: cannot resolve workspace")
			return 2
		}
		root = cwd
	}
	text := secure.audit_all(root)
	defer delete(text)
	fmt.println(text)
	if secure.has_high(text) {
		return 1
	}
	return 0
}
