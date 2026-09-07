// SPDX-License-Identifier: 0BSD
/*
Deterministic next-action controller (no LLM).
*/

package agent

Controller_Action :: enum {
	Edit,
	Verify,
	Review,
	Stop,
	Compact,
}

controller_action_string :: proc(a: Controller_Action) -> string {
	switch a {
	case .Edit:
		return "edit"
	case .Verify:
		return "verify"
	case .Review:
		return "review"
	case .Stop:
		return "stop"
	case .Compact:
		return "compact"
	}
	return "stop"
}

/*
Suggest the next harness action from a structured run summary.
*/
suggest_next_action :: proc(
	had_writes: bool,
	verify_ok: bool,
	verify_ran: bool,
	block_findings: int,
	context_chars: int,
	compact_budget: int,
) -> Controller_Action {
	if compact_budget > 0 && context_chars > (compact_budget * 70) / 100 {
		return .Compact
	}
	if had_writes && !verify_ran {
		return .Verify
	}
	if had_writes && verify_ran && !verify_ok {
		return .Edit
	}
	if had_writes && verify_ok && block_findings > 0 {
		return .Edit
	}
	if had_writes && verify_ok && block_findings == 0 {
		return .Review
	}
	if !had_writes {
		return .Stop
	}
	return .Stop
}
