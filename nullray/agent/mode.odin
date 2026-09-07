// SPDX-License-Identifier: 0BSD
/*
Agent interaction mode, switch policy, and review env helpers.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

Agent_Mode :: enum {
	Ask,
	Plan,
	Review,
	Edit,
}

/*
Manual: user only switches mode.
Auto: heuristic switch from user text.
Model: model may request switch via MODE lines.
*/
Mode_Policy :: enum {
	Manual,
	Auto,
	Model,
}

REVIEW_PROMPT :: `You are a separate code reviewer. Review the DIFF only for correctness, risks, regressions, and test gaps.
Reply with structured findings. Each finding on its own line:
SEVERITY|path|reason
SEVERITY is block, warn, or note.
End with FINDINGS: N or FINDINGS: none.
Do not rewrite the code. Be brief.`

RUBRIC_PROMPT :: `Score the DIFF for readable structured code on these dimensions (0-100 each):
structure, naming, comments_prose, ownership_idioms, test_honesty.
Reply with lines: DIM=score
Then TOTAL=weighted_average and PASS=yes|no (pass if TOTAL>=80).
Be brief.`

mode_from_string :: proc(s: string) -> (Agent_Mode, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "ask":
		return .Ask, true
	case "plan":
		return .Plan, true
	case "review":
		return .Review, true
	case "edit":
		return .Edit, true
	}
	return .Edit, false
}

mode_string :: proc(m: Agent_Mode) -> string {
	switch m {
	case .Ask:
		return "ask"
	case .Plan:
		return "plan"
	case .Review:
		return "review"
	case .Edit:
		return "edit"
	}
	return "edit"
}

policy_from_string :: proc(s: string) -> (Mode_Policy, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "manual":
		return .Manual, true
	case "auto":
		return .Auto, true
	case "model":
		return .Model, true
	}
	return .Manual, false
}

policy_string :: proc(p: Mode_Policy) -> string {
	switch p {
	case .Manual:
		return "manual"
	case .Auto:
		return "auto"
	case .Model:
		return "model"
	}
	return "manual"
}

mode_from_env :: proc() -> Agent_Mode {
	if v, ok := os.lookup_env(constants.ENV_MODE, context.temp_allocator); ok {
		if m, found := mode_from_string(v); found {
			return m
		}
	}
	return .Edit
}

policy_from_env :: proc() -> Mode_Policy {
	if v, ok := os.lookup_env(constants.ENV_MODE_POLICY, context.temp_allocator); ok {
		if p, found := policy_from_string(v); found {
			return p
		}
	}
	return .Manual
}

tools_for_mode :: proc(mode: Agent_Mode) -> (allow_write: bool, allow_shell: bool, allow_read: bool) {
	switch mode {
	case .Ask, .Plan, .Review:
		return false, false, true
	case .Edit:
		return true, true, true
	}
	return true, true, true
}

mode_prompt_section :: proc(mode: Agent_Mode, policy: Mode_Policy, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	mode_name := mode_string(mode)
	strings.write_string(&b, "## Agent mode\n\n")
	strings.write_string(&b, fmt.aprintf("Current mode: %s.\n", mode_name, allocator = allocator))
	switch mode {
	case .Ask:
		strings.write_string(
			&b,
			"Ask mode: read-only. Answer questions about the codebase without modifying files or running shell commands.\n",
		)
		strings.write_string(
			&b,
			"Put explanations and code snippets in chat when helpful. Do not call write/edit/shell tools.\n",
		)
	case .Plan:
		strings.write_string(
			&b,
			"Plan mode: read-only. Explore the codebase and propose an approach without making changes.\n",
		)
		strings.write_string(
			&b,
			"Write a complete markdown plan with these sections (use these exact headings):\n",
		)
		strings.write_string(
			&b,
			"## Goal\n## Scope\n## Steps\n## Risks\n## Verify\n## Success\n## Budget\n## Failure\n",
		)
		strings.write_string(
			&b,
			"Verify must list exact shell commands. Budget must name a step or turn cap. Success and Failure are terminal conditions.\n",
		)
		strings.write_string(
			&b,
			"In non-interactive runs, state assumptions instead of asking clarifying questions.\n",
		)
		strings.write_string(
			&b,
			"The runtime saves the plan to a .md file and validates required sections before edit mode.\n",
		)
		strings.write_string(
			&b,
			"Do not edit project source or run shell until edit mode.\n",
		)
	case .Review:
		strings.write_string(
			&b,
			"Review mode: read-only. Review code, diffs, or PRs for correctness, security, and regressions.\n",
		)
		strings.write_string(
			&b,
			"Order findings by severity. Cite file:line when possible. Skip drive-by refactors and style nits.\n",
		)
		strings.write_string(
			&b,
			"End the reply with a single trailer line exactly one of: FINDINGS: none  or  FINDINGS: N  (N is a positive integer).\n",
		)
		strings.write_string(
			&b,
			"Do not call write/edit/shell tools.\n",
		)
	case .Edit:
		strings.write_string(
			&b,
			"Edit mode: full access. Read, edit files, and run shell commands as needed.\n",
		)
		strings.write_string(
			&b,
			"Apply changes with write_file, edit_file, or apply_edits. Do not paste large code dumps into chat unless the user asked to see the code here.\n",
		)
		strings.write_string(
			&b,
			"Keep chat replies short: what you changed and why. Prefer tools over transcript code blocks.\n",
		)
	}
	if policy == .Auto || policy == .Model {
		strings.write_string(&b, "\nWhen a different mode fits better, emit a single line on its own:\n")
		strings.write_string(&b, "MODE ask\nMODE plan\nMODE review\nMODE edit\n")
		if policy == .Auto {
			strings.write_string(&b, "The runtime may also switch modes based on user input heuristics.\n")
		}
	}
	return strings.to_string(b)
}

detect_mode_request :: proc(text: string, allocator := context.allocator) -> (Agent_Mode, bool, string) {
	lines := strings.split_lines(text, context.temp_allocator)
	found_mode: Agent_Mode
	found := false
	out: strings.Builder
	strings.builder_init(&out, allocator)
	first := true
	for line in lines {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "MODE ") {
			rest := strings.trim_space(trimmed[5:])
			if m, ok := mode_from_string(rest); ok {
				found_mode = m
				found = true
				continue
			}
		}
		if !first {
			strings.write_string(&out, "\n")
		}
		first = false
		strings.write_string(&out, line)
	}
	return found_mode, found, strings.to_string(out)
}

@(private)
ASK_KEYWORDS :: []string{
	"explain",
	"what is",
	"what's",
	"how does",
	"how do",
	"why does",
	"why is",
	"describe",
}

@(private)
PLAN_KEYWORDS :: []string{"plan", "design", "approach", "architect", "strategy", "roadmap"}

@(private)
REVIEW_KEYWORDS :: []string{"review", "pr review", "look over", "code review", "audit"}

@(private)
EDIT_KEYWORDS :: []string{
	"fix",
	"implement",
	"edit",
	"create",
	"write",
	"add",
	"remove",
	"delete",
	"update",
	"change",
	"refactor",
	"build",
	"make",
}

auto_suggest_mode :: proc(user_text: string) -> Agent_Mode {
	lower := strings.to_lower(user_text, context.temp_allocator)
	for kw in REVIEW_KEYWORDS {
		if strings.contains(lower, kw) {
			return .Review
		}
	}
	for kw in ASK_KEYWORDS {
		if strings.contains(lower, kw) {
			return .Ask
		}
	}
	for kw in PLAN_KEYWORDS {
		if strings.contains(lower, kw) {
			return .Plan
		}
	}
	for kw in EDIT_KEYWORDS {
		if strings.contains(lower, kw) {
			return .Edit
		}
	}
	return .Edit
}

review_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_REVIEW, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "on", "1", "true", "yes":
			return true
		case "off", "0", "false", "no":
			return false
		}
	}
	return false
}

review_model_from_env :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_REVIEW_MODEL, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	return ""
}
