// SPDX-License-Identifier: 0BSD
/*
Controller and plan contract unit tests.
*/

package agent

import "core:os"
import "core:strings"
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
test_plan_apply_note_includes_steps :: proc(t: ^testing.T) {
	body := `## Goal
Do the thing

## Verify
make test

## Success
done

## Budget
1

## Steps
1. Edit foo
2. Run tests
`
	note := plan_apply_note(body, 2)
	defer delete(note)
	testing.expect(t, strings.contains(note, "Do the thing"))
	testing.expect(t, strings.contains(note, "make test"))
	testing.expect(t, strings.contains(note, "Edit foo"))
	testing.expect(t, strings.contains(note, "Steps:"))
}

@(test)
test_load_plan_file_ok_and_missing :: proc(t: ^testing.T) {
	body, err := load_plan_file("/tmp/nullray-plan-in-missing-xyz.md")
	testing.expect(t, len(err) > 0)
	testing.expect_value(t, body, "")
	delete(err)

	root := "/tmp/nullray-plan-in-test"
	_ = os.make_directory_all(root)
	path := "/tmp/nullray-plan-in-test/ok.md"
	ok_body := "## Goal\nG\n\n## Verify\nmake test\n\n## Success\nok\n\n## Budget\n1\n\n## Steps\n1. x\n"
	testing.expect(t, os.write_entire_file(path, ok_body) == nil)
	loaded, lerr := load_plan_file(path)
	defer delete(loaded)
	testing.expect_value(t, lerr, "")
	testing.expect(t, strings.contains(loaded, "## Verify"))

	bad := "/tmp/nullray-plan-in-test/bad.md"
	testing.expect(t, os.write_entire_file(bad, "## Goal\nonly\n") == nil)
	_, berr := load_plan_file(bad)
	testing.expect(t, len(berr) > 0)
	delete(berr)
}

@(test)
test_validate_plan_contract_missing :: proc(t: ^testing.T) {
	body := "## Goal\nDo stuff\n\n## Steps\n1. x\n"
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	testing.expect(t, !c.valid)
}

@(test)
test_validate_plan_contract_requires_steps :: proc(t: ^testing.T) {
	body := `## Goal
G

## Verify
make test

## Success
ok

## Budget
1
`
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	testing.expect(t, !c.valid)
	testing.expect(t, strings.contains(c.err, "Steps"))
}

@(test)
test_first_verify_command :: proc(t: ^testing.T) {
	cmd := first_verify_command("- `make test`\n- make lint\n")
	defer delete(cmd)
	testing.expect_value(t, cmd, "make test")
}

@(test)
test_lint_plan_contract_non_blocking :: proc(t: ^testing.T) {
	body := `## Goal
G

## Steps
- do a thing

## Verify
please run tests somehow

## Success
ok

## Budget
a few tries
`
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	testing.expect(t, c.valid)
	hint := lint_plan_contract(body)
	defer delete(hint)
	testing.expect(t, len(hint) > 0)
	testing.expect(t, strings.contains(hint, "numbered") || strings.contains(hint, "Budget") || strings.contains(hint, "Verify"))
}

@(test)
test_plan_repair_nudge :: proc(t: ^testing.T) {
	nudge := plan_repair_nudge("plan missing required sections: Verify")
	defer delete(nudge)
	testing.expect(t, strings.contains(nudge, "## Steps"))
	testing.expect(t, strings.contains(nudge, "Verify"))
}

@(test)
test_parse_plan_steps_numbered :: proc(t: ^testing.T) {
	steps := parse_plan_steps("1. First\n2. Second\n3. Third\n")
	defer plan_steps_destroy(&steps)
	testing.expect_value(t, len(steps), 3)
	testing.expect_value(t, steps[0], "First")
	testing.expect_value(t, steps[2], "Third")
}

@(test)
test_parse_plan_steps_fallback :: proc(t: ^testing.T) {
	steps := parse_plan_steps("- alpha\n- beta\n")
	defer plan_steps_destroy(&steps)
	testing.expect_value(t, len(steps), 2)
}

@(test)
test_plan_step_apply_note_current :: proc(t: ^testing.T) {
	body := `## Goal
Do the thing

## Verify
make test

## Success
done

## Budget
1

## Steps
1. Edit foo
2. Run tests
`
	steps := parse_plan_steps(section_body(body, "Steps", context.temp_allocator))
	defer plan_steps_destroy(&steps)
	note := plan_step_apply_note(body, 0, steps[:], 2)
	defer delete(note)
	testing.expect(t, strings.contains(note, "Current step 1/2"))
	testing.expect(t, strings.contains(note, "Edit foo"))
	testing.expect(t, !strings.contains(note, "Run tests"))
}

@(test)
test_load_plan_example_excerpt :: proc(t: ^testing.T) {
	ex := load_plan_example_excerpt()
	defer delete(ex)
	testing.expect(t, strings.contains(ex, "## Goal"))
	testing.expect(t, strings.contains(ex, "## Steps"))
}

@(test)
test_format_architect_summary_ok :: proc(t: ^testing.T) {
	body := "## Goal\nG\n\n## Steps\n1. x\n\n## Verify\nmake test\n\n## Success\nok\n\n## Budget\n1\n"
	sum := format_architect_summary(body, context.allocator)
	defer delete(sum)
	testing.expect(t, strings.contains(sum, "## Goal"))
	testing.expect(t, !strings.contains(sum, "incomplete"))
}

@(test)
test_format_architect_summary_soft_fail :: proc(t: ^testing.T) {
	sum := format_architect_summary("just vibes", context.allocator)
	defer delete(sum)
	testing.expect(t, strings.contains(sum, "incomplete"))
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
