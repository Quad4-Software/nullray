// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Auto mode suggestion keyword heuristics.
*/

package agent

import "core:strings"


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
PLAN_KEYWORDS :: []string{
	"plan",
	"design",
	"approach",
	"architect",
	"strategy",
	"roadmap",
	"scaffold",
	"bootstrap",
	"greenfield",
	"new project",
	"new repo",
}

@(private)
REVIEW_KEYWORDS :: []string{
	"review",
	"pr review",
	"look over",
	"code review",
	"audit",
	"hunt",
	"vuln",
	"vulnerab",
	"security bug",
	"cve",
	"pentest",
	"adversarial",
	"oracle",
}

@(private)
ORCHESTRATE_KEYWORDS :: []string{
	"orchestrate",
	"orchestrator",
	"delegate",
	"fan out",
	"fan-out",
	"multi-agent",
	"multiagent",
	"parallel agents",
	"coordinate agents",
}

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
	for kw in ORCHESTRATE_KEYWORDS {
		if strings.contains(lower, kw) {
			return .Orchestrate
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
