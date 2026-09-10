// SPDX-License-Identifier: 0BSD
package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:vcs"

slash_cmd_review :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "on" {
		os.set_env(constants.ENV_REVIEW, "on")
		session.session_set_status(&a.session, "review on")
		return
	}
	if rest == "off" {
		os.set_env(constants.ENV_REVIEW, "off")
		session.session_set_status(&a.session, "review off")
		return
	}
	lower := strings.to_lower(rest, context.temp_allocator)
	if lower == "local" || strings.has_prefix(lower, "local ") {
		arg := ""
		if len(rest) > 5 {
			arg = strings.trim_space(rest[5:])
		}
		slash_review_local(a, arg)
		return
	}
	on := agent.review_enabled_from_env()
	session.session_set_status(
		&a.session,
		fmt.tprintf("review %s (NULLRAY_REVIEW_MODEL optional, /review local [scope])", on ? "on" : "off"),
	)
}

slash_review_local :: proc(a: ^App, args: string) {
	root := sandbox.workspace_current()
	if len(root) == 0 {
		cwd, err := os.get_working_directory(context.temp_allocator)
		if err != nil {
			session.session_set_status(&a.session, "review local: no workspace")
			return
		}
		root = cwd
	}

	scope := vcs.Diff_Scope.Working
	base := ""
	fields := strings.fields(strings.trim_space(args))
	if len(fields) >= 1 {
		if s, ok := vcs.scope_from_string(fields[0]); ok {
			scope = s
			if scope == .Base && len(fields) >= 2 {
				base = fields[1]
			}
		} else {
			scope = .Base
			base = fields[0]
		}
	}
	if scope == .Base && len(strings.trim_space(base)) == 0 {
		session.session_set_status(&a.session, "usage: /review local [working|staged|unstaged|base REF]")
		return
	}

	repo := vcs.detect(root)
	defer vcs.repo_destroy(&repo)
	if repo.kind == .None {
		session.session_set_status(&a.session, "review local: no Git or Fossil repo")
		return
	}
	diff, label, err := vcs.collect_review_diff(repo, vcs.Diff_Opts{scope = scope, base = base})
	defer delete(diff)
	defer delete(label)
	if len(err) > 0 {
		session.session_set_status(&a.session, fmt.tprintf("review local: %s", err))
		delete(err)
		return
	}
	if len(strings.trim_space(diff)) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("review local: no changes (%s)", label))
		return
	}

	p := provider.registry_active(&a.registry)
	if p == nil || p.chat == nil {
		session.session_set_status(&a.session, "review local: no provider")
		return
	}
	payload := agent.review_bot_user_payload(vcs.kind_name(repo.kind), label, diff)
	defer delete(payload)
	text, rerr := agent.run_diff_review(p, payload, true)
	if len(rerr) > 0 {
		session.session_set_status(&a.session, fmt.tprintf("review local: %s", rerr))
		delete(rerr)
		return
	}
	if len(text) == 0 {
		session.session_set_status(&a.session, "review local: empty reply")
		return
	}
	blocks, total := agent.parse_block_findings(text)
	session.session_push_assistant(&a.session, text)
	delete(text)
	session.session_set_status(
		&a.session,
		fmt.tprintf("review local %s: findings=%d blocking=%d", label, total, blocks),
	)
}
