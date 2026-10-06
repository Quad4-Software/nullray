// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
In-turn architect then editor. The architect model writes a Done Contract,
then the editor model executes it. Models come from models.json roles
architect (or explore) and edit.
*/

package run

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:subagent"

architect_plan_prompt :: proc(user: string, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"You are the architect. Explore if needed, then output one markdown Done Contract for the editor. Exact headings:\n## Goal\n## Scope\n## Steps\n## Risks\n## Verify\n## Success\n## Budget\n## Failure\nNumber Steps. Verify must list a real shell command. Do not edit files. Task:\n\n%s",
		user,
		allocator = allocator,
	)
}

run_architect_print :: proc(cfg: Config) -> Result {
	saved_model, had_model := os.lookup_env(constants.ENV_MODEL, context.allocator)
	defer if had_model {
		os.set_env(constants.ENV_MODEL, saved_model)
		delete(saved_model)
	} else {
		os.unset_env(constants.ENV_MODEL)
	}
	saved_mode, had_mode := os.lookup_env(constants.ENV_MODE, context.allocator)
	defer if had_mode {
		os.set_env(constants.ENV_MODE, saved_mode)
		delete(saved_mode)
	} else {
		os.unset_env(constants.ENV_MODE)
	}

	reg: provider.Registry
	provider.registry_init(&reg)
	p := provider.registry_active(&reg)
	def := ""
	main := ""
	if p != nil {
		def = p.default_model
		main = p.default_model
	}
	arch_model, _ := subagent.policy_resolve("architect", "", def, main, context.temp_allocator)
	if len(arch_model) == 0 {
		arch_model, _ = subagent.policy_resolve("explore", "", def, main, context.temp_allocator)
	}
	edit_model, _ := subagent.policy_resolve("edit", "", def, main, context.temp_allocator)
	provider.registry_destroy(&reg)

	os.set_env(constants.ENV_MODE, "ask")
	if len(arch_model) > 0 {
		os.set_env(constants.ENV_MODEL, arch_model)
	}
	arch_cfg := cfg
	arch_cfg.architect = false
	arch_cfg.samples = 1
	arch_cfg.prompt = architect_plan_prompt(cfg.prompt, context.temp_allocator)
	fmt.eprintln("nullray: architect turn")
	plan := run_print_inner(arch_cfg)
	if !plan.ok && len(plan.text) == 0 {
		return plan
	}
	exec := fmt.tprintf("Execute this approved Done Contract. Do not rewrite the plan.\n\n%s", plan.text)
	result_destroy(&plan)
	os.set_env(constants.ENV_MODE, "edit")
	if len(edit_model) > 0 {
		os.set_env(constants.ENV_MODEL, edit_model)
	}
	if _, ok := os.lookup_env(constants.ENV_PERMS, context.temp_allocator); !ok {
		os.set_env(constants.ENV_PERMS, "allow")
	}
	edit_cfg := cfg
	edit_cfg.architect = false
	edit_cfg.samples = 1
	edit_cfg.prompt = exec
	fmt.eprintln("nullray: editor turn")
	return run_print_inner(edit_cfg)
}
