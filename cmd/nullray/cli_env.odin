// SPDX-License-Identifier: 0BSD
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

apply_cli_env :: proc(cli: ^Cli) {
	if len(cli.plan_in) > 0 {
		os.set_env(constants.ENV_PLAN_IN, cli.plan_in)
	}
	if cli.print_mode {
		os.set_env(constants.ENV_PRINT, "1")
		if !cli.ephemeral && len(cli.session) == 0 {
			os.set_env(constants.ENV_EPHEMERAL, "1")
		}
		if cli.ask_simple {
			os.set_env(constants.ENV_ASK_SIMPLE, "1")
			if len(cli.mode) == 0 {
				os.set_env(constants.ENV_MODE, "ask")
			}
			if len(cli.perms) == 0 {
				if _, ok := os.lookup_env(constants.ENV_PERMS, context.temp_allocator); !ok {
					os.set_env(constants.ENV_PERMS, "ask")
				}
			}
		} else if len(cli.mode) == 0 {
			if _, ok := os.lookup_env(constants.ENV_MODE, context.temp_allocator); !ok {
				has_plan_in := len(cli.plan_in) > 0
				if !has_plan_in {
					if v, pok := os.lookup_env(constants.ENV_PLAN_IN, context.temp_allocator); pok && len(v) > 0 {
						has_plan_in = true
					}
				}
				if has_plan_in {
					os.set_env(constants.ENV_MODE, "edit")
				} else {
					os.set_env(constants.ENV_MODE, "ask")
				}
			}
		}
	}
	if cli.ephemeral {
		os.set_env(constants.ENV_EPHEMERAL, "1")
	}
	if cli.bare {
		os.set_env(constants.ENV_BARE, "1")
	}
	if len(cli.skills_paths) > 0 {
		os.set_env(constants.ENV_SKILLS, cli.skills_paths)
	}
	if cli.fail_on_findings {
		os.set_env(constants.ENV_FAIL_ON_FINDINGS, "1")
	}
	if len(cli.provider) > 0 {
		os.set_env(constants.ENV_PROVIDER, cli.provider)
	}
	if len(cli.model) > 0 {
		os.set_env(constants.ENV_MODEL, cli.model)
	}
	if len(cli.theme) > 0 {
		os.set_env(constants.ENV_THEME, cli.theme)
	}
	if len(cli.mode) > 0 {
		os.set_env(constants.ENV_MODE, cli.mode)
	}
	if len(cli.hunt) > 0 {
		os.set_env(constants.ENV_HUNT, cli.hunt)
		if len(cli.mode) == 0 {
			if _, ok := os.lookup_env(constants.ENV_MODE, context.temp_allocator); !ok {
				os.set_env(constants.ENV_MODE, "review")
			}
		}
	}
	if len(cli.perms) > 0 {
		os.set_env(constants.ENV_PERMS, cli.perms)
	}
	if len(cli.gate) > 0 {
		os.set_env(constants.ENV_GATE, cli.gate)
	}
	if len(cli.sandbox) > 0 {
		os.set_env(constants.ENV_SANDBOX, cli.sandbox)
	}
	if cli.no_elevate {
		os.set_env(constants.ENV_ELEVATE, "deny")
	}
	if len(cli.workspace) > 0 {
		os.set_env(constants.ENV_WORKSPACE, cli.workspace)
	}
	if len(cli.session) > 0 {
		os.set_env(constants.ENV_SESSION, cli.session)
	}
	if len(cli.keys) > 0 {
		os.set_env(constants.ENV_KEYS, cli.keys)
	}
	if len(cli.out_path) > 0 {
		os.set_env(constants.ENV_OUT, cli.out_path)
	}
	if len(cli.plan_out) > 0 {
		os.set_env(constants.ENV_PLAN_OUT, cli.plan_out)
	}
	if len(cli.output_format) > 0 {
		os.set_env(constants.ENV_OUTPUT_FORMAT, cli.output_format)
	}
	if cli.timeout_sec > 0 {
		os.set_env(constants.ENV_PRINT_TIMEOUT, fmt.tprintf("%d", cli.timeout_sec))
	}
	if len(cli.message_file) > 0 {
		os.set_env(constants.ENV_MESSAGE_FILE, cli.message_file)
	}
	if cli.no_splash {
		os.set_env(constants.ENV_SPLASH, "0")
	} else if cli.splash {
		os.set_env(constants.ENV_SPLASH, "1")
	}
	if cli.no_subagents {
		os.set_env(constants.ENV_SUBAGENTS, "0")
	}
	if cli.hide_sensitive {
		os.set_env(constants.ENV_HIDE_SENSITIVE, "1")
	}
	if cli.print_strict {
		os.set_env(constants.ENV_PRINT_STRICT, "1")
	}
	if cli.auto {
		os.set_env(constants.ENV_AUTO, "1")
	}
	if cli.print_usage {
		os.set_env(constants.ENV_PRINT_USAGE, "1")
	}
	if cli.debug {
		os.set_env(constants.ENV_DEBUG, "1")
	}
	grant_cli_sandbox_paths(cli)
}

/*
Landlock only allows the workspace plus a private tmp root. Print-mode CLI
paths outside that set (--message-file, --plan-in, --out, --plan-out) need
explicit EXTRA_RO / EXTRA_RW or the open fails with Permission_Denied.
*/
grant_cli_sandbox_paths :: proc(cli: ^Cli) {
	ro := make([dynamic]string, context.temp_allocator)
	rw := make([dynamic]string, context.temp_allocator)
	// Parent dirs: landlock RO grants are directory-oriented.
	append_abs_parent(&ro, cli.message_file)
	append_abs_parent(&ro, cli.plan_in)
	append_abs_parent(&rw, cli.out_path)
	append_abs_parent(&rw, cli.plan_out)
	if len(ro) == 0 && len(rw) == 0 {
		return
	}
	if len(ro) > 0 {
		merge_path_env(constants.ENV_SANDBOX_EXTRA_RO, ro[:])
	}
	if len(rw) > 0 {
		merge_path_env(constants.ENV_SANDBOX_EXTRA_RW, rw[:])
	}
}

append_abs_parent :: proc(dst: ^[dynamic]string, path: string) {
	if len(path) == 0 {
		return
	}
	abs := abs_cli_path(path)
	if len(abs) == 0 {
		return
	}
	parent := filepath.dir(abs)
	if len(parent) == 0 {
		parent = abs
	}
	append(dst, parent)
}

abs_cli_path :: proc(path: string) -> string {
	if filepath.is_abs(path) {
		return path
	}
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return path
	}
	joined, jerr := filepath.join({cwd, path}, context.temp_allocator)
	if jerr != nil {
		return path
	}
	return joined
}

merge_path_env :: proc(key: string, add: []string) {
	if len(add) == 0 {
		return
	}
	parts := make([dynamic]string, context.temp_allocator)
	if v, ok := os.lookup_env(key, context.temp_allocator); ok && len(v) > 0 {
		for p in strings.split(v, ",", context.temp_allocator) {
			t := strings.trim_space(p)
			if len(t) > 0 {
				append(&parts, t)
			}
		}
	}
	for a in add {
		dup := false
		for p in parts {
			if p == a {
				dup = true
				break
			}
		}
		if !dup {
			append(&parts, a)
		}
	}
	os.set_env(key, strings.join(parts[:], ",", context.temp_allocator))
}

env_or :: proc(key, fallback: string) -> string {
	if v, ok := os.lookup_env(key, context.temp_allocator); ok {
		return v
	}
	return fallback
}
