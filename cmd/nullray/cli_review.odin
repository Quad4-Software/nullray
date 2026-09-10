// SPDX-License-Identifier: 0BSD
/*
Local VCS-agnostic review bot (CodeRabbit-style scopes, no forge).
*/

package main

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:http"
import "nullray:provider"
import "nullray:vcs"

run_review_bot :: proc(cli: ^Cli) -> int {
	if !http.global_init() {
		fmt.eprintln("nullray: TLS init failed")
		return 1
	}
	defer http.global_cleanup()

	root := cli.workspace
	if len(root) == 0 {
		if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
			root = v
		}
	}
	if len(root) == 0 {
		cwd, err := os.get_working_directory(context.temp_allocator)
		if err != nil {
			fmt.eprintln("nullray: review: cannot resolve workspace")
			return 2
		}
		root = cwd
	}

	scope, base, paths, perr := review_opts_from_cli(cli)
	if len(perr) > 0 {
		fmt.eprintln("nullray:", perr)
		return 2
	}
	defer {
		delete(base)
		for p in paths {
			delete(p)
		}
		delete(paths)
	}

	repo := vcs.detect(root)
	defer vcs.repo_destroy(&repo)
	if repo.kind == .None {
		fmt.eprintln("nullray: review: no Git or Fossil repository in", root)
		return 2
	}

	diff, label, derr := vcs.collect_review_diff(
		repo,
		vcs.Diff_Opts{
			scope = scope,
			base = base,
			paths = paths[:],
			include_untracked = cli.review_untracked || review_untracked_from_env(),
		},
	)
	defer delete(diff)
	defer delete(label)
	if len(derr) > 0 {
		fmt.eprintln("nullray: review:", derr)
		delete(derr)
		return 2
	}
	if len(strings.trim_space(diff)) == 0 {
		hint := ""
		if !cli.review_untracked && !review_untracked_from_env() &&
		   (scope == .Working || scope == .Unstaged) {
			hint = " (try --include-untracked for new files)"
		}
		fmt.printf("nullray: review: no changes for scope %s%s\n", label, hint)
		return 0
	}

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)
	p := provider.registry_active(&reg)
	if p == nil || p.chat == nil {
		fmt.eprintln("nullray: review: no provider")
		return 2
	}

	payload := agent.review_bot_user_payload(vcs.kind_name(repo.kind), label, diff)
	defer delete(payload)
	text, err := agent.run_diff_review(p, payload, true)
	defer delete(text)
	if len(err) > 0 {
		fmt.eprintln("nullray: review:", err)
		delete(err)
		return 2
	}
	if len(text) == 0 {
		fmt.eprintln("nullray: review: empty reply")
		return 2
	}

	blocks, total := agent.parse_block_findings(text)
	n, found := agent.parse_findings_trailer(text)
	if !found {
		n = total
	}

	fmt_out := cli.output_format
	if len(fmt_out) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OUTPUT_FORMAT, context.temp_allocator); ok {
			fmt_out = v
		}
	}
	if strings.to_lower(fmt_out, context.temp_allocator) == "json" {
		items := agent.parse_findings_list(text)
		defer agent.findings_destroy(items)
		js := agent.findings_to_json(items, n, found)
		defer delete(js)
		fmt.println(js)
	} else {
		fmt.printf("nullray: review vcs=%s scope=%s\n\n", vcs.kind_name(repo.kind), label)
		fmt.println(text)
		if found || total > 0 {
			fmt.printf("\nnullray: findings=%d blocking=%d\n", n, blocks)
		}
	}

	if len(cli.out_path) > 0 {
		if os.write_entire_file(cli.out_path, transmute([]u8)text) != nil {
			fmt.eprintln("nullray: review: write --out failed")
			return 2
		}
	}

	fail := cli.fail_on_findings || agent.fail_on_findings_from_env()
	if fail && (blocks > 0 || n > 0) {
		return 1
	}
	return 0
}

review_opts_from_cli :: proc(
	cli: ^Cli,
) -> (
	scope: vcs.Diff_Scope,
	base: string,
	paths: [dynamic]string,
	err: string,
) {
	scope = .Working
	if len(cli.review_scope) > 0 {
		s, ok := vcs.scope_from_string(cli.review_scope)
		if !ok {
			return .Working, "", nil, strings.clone("unknown --review-scope (working|staged|unstaged|base)")
		}
		scope = s
	} else if v, ok := os.lookup_env(constants.ENV_REVIEW_SCOPE, context.temp_allocator); ok && len(v) > 0 {
		s, sok := vcs.scope_from_string(v)
		if !sok {
			return .Working, "", nil, strings.clone("unknown NULLRAY_REVIEW_SCOPE")
		}
		scope = s
	}
	if cli.review_staged {
		scope = .Staged
	}
	if cli.review_unstaged {
		scope = .Unstaged
	}
	if cli.review_staged && cli.review_unstaged {
		return .Working, "", nil, strings.clone("--staged and --unstaged cannot both be set")
	}

	base = ""
	if len(cli.review_base) > 0 {
		base = strings.clone(cli.review_base)
		if scope == .Working && !cli.review_staged && !cli.review_unstaged && len(cli.review_scope) == 0 {
			scope = .Base
		}
	} else if v, ok := os.lookup_env(constants.ENV_REVIEW_BASE, context.temp_allocator); ok && len(v) > 0 {
		base = strings.clone(v)
		if scope == .Working && !cli.review_staged && !cli.review_unstaged && len(cli.review_scope) == 0 {
			scope = .Base
		}
	}
	if scope == .Base && len(strings.trim_space(base)) == 0 {
		delete(base)
		return .Working, "", nil, strings.clone("base review needs --base REF or NULLRAY_REVIEW_BASE")
	}

	paths = make([dynamic]string)
	path_src := cli.review_paths
	if len(path_src) == 0 {
		if v, ok := os.lookup_env(constants.ENV_REVIEW_PATHS, context.temp_allocator); ok {
			path_src = v
		}
	}
	if len(path_src) > 0 {
		for p in strings.split(path_src, ",", context.temp_allocator) {
			t := strings.trim_space(p)
			if len(t) > 0 {
				append(&paths, strings.clone(t))
			}
		}
	}
	return scope, base, paths, ""
}

review_untracked_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_REVIEW_UNTRACKED, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}
