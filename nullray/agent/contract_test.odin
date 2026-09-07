// SPDX-License-Identifier: 0BSD
/*
Controller and plan contract unit tests.
*/

package agent

import "core:testing"

@(test)
test_validate_plan_contract_ok :: proc(t: ^testing.T) {
	body := `# Title

## Goal
Ship progressive skills.

## Scope
nullray/skills

## Steps
1. Parse frontmatter

## Risks
Cache bust

## Verify
make test

## Success
Catalog loads without bodies

## Budget
3 verify retries

## Failure
Repeated schema dump
`
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	testing.expect(t, c.valid)
	testing.expect(t, len(c.verify) > 0)
}

@(test)
test_validate_plan_contract_missing :: proc(t: ^testing.T) {
	body := "## Goal\nDo stuff\n\n## Steps\n1. x\n"
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	testing.expect(t, !c.valid)
}

@(test)
test_first_verify_command :: proc(t: ^testing.T) {
	cmd := first_verify_command("- `make test`\n- make lint\n")
	defer delete(cmd)
	testing.expect_value(t, cmd, "make test")
}

@(test)
test_suggest_next_action :: proc(t: ^testing.T) {
	testing.expect_value(t, suggest_next_action(true, false, false, 0, 1000, 10000), Controller_Action.Verify)
	testing.expect_value(t, suggest_next_action(true, false, true, 0, 1000, 10000), Controller_Action.Edit)
	testing.expect_value(t, suggest_next_action(true, true, true, 2, 1000, 10000), Controller_Action.Edit)
	testing.expect_value(t, suggest_next_action(false, true, true, 0, 9000, 10000), Controller_Action.Compact)
}

@(test)
test_parse_block_findings :: proc(t: ^testing.T) {
	text := "block|a.odin|leak\nwarn|b.odin|style\nFINDINGS: 2\n"
	blocks, total := parse_block_findings(text)
	testing.expect_value(t, blocks, 1)
	testing.expect(t, total >= 2)
}

@(test)
test_shell_output_ok :: proc(t: ^testing.T) {
	testing.expect(t, shell_output_ok("exit_code=0\nok"))
	testing.expect(t, !shell_output_ok("exit_code=1\nfail"))
}
