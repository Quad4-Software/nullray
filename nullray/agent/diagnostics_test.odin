// SPDX-License-Identifier: 0BSD
package agent

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_parse_gcc_diag :: proc(t: ^testing.T) {
	out := "foo.c:12:5: error: expected ';' before '}' token\n"
	findings := parse_diagnostics(out)
	defer delete_findings(&findings)
	testing.expect(t, len(findings) >= 1)
	testing.expect(t, strings.contains(findings[0].path, "foo.c"))
	testing.expect_value(t, findings[0].line, 12)
}

@(test)
test_parse_rustc_diag :: proc(t: ^testing.T) {
	out := "error[E0308]: mismatched types\n --> src/main.rs:10:5\n"
	findings := parse_diagnostics(out)
	defer delete_findings(&findings)
	testing.expect(t, len(findings) >= 1)
	testing.expect(t, strings.contains(findings[0].path, "main.rs"))
}

@(test)
test_parse_odin_diag :: proc(t: ^testing.T) {
	out := "/tmp/x.odin(42:3) Error: Undeclared name: foo\n"
	findings := parse_diagnostics(out)
	defer delete_findings(&findings)
	testing.expect(t, len(findings) >= 1)
	testing.expect_value(t, findings[0].line, 42)
}

@(test)
test_parse_tsc_diag :: proc(t: ^testing.T) {
	out := "src/a.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'.\n"
	findings := parse_diagnostics(out)
	defer delete_findings(&findings)
	testing.expect(t, len(findings) >= 1)
	testing.expect_value(t, findings[0].line, 3)
	testing.expect_value(t, findings[0].col, 7)
}

@(test)
test_findings_cap :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for i in 0 ..< 20 {
		fmt.sbprintf(&b, "f%d.c:1:1: error: boom\n", i)
	}
	findings := parse_diagnostics(strings.to_string(b))
	defer delete_findings(&findings)
	testing.expect(t, len(findings) <= constants.MAX_VERIFY_FINDINGS)
}

@(test)
test_nudge_with_artifact_short :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_LID, "1")
	defer os.unset_env(constants.ENV_LID)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "foo.c:1:1: error: nope\n")
	for _ in 0 ..< 5000 {
		strings.write_string(&b, "error line\n")
	}
	log := strings.to_string(b)
	msg := format_verify_nudge("make test", 1, 3, log, false, context.allocator, "a_test")
	defer delete(msg)
	testing.expect(t, strings.has_prefix(msg, VERIFY_USER_PREFIX))
	testing.expect(t, strings.contains(msg, "artifact=a_test"))
	testing.expect(t, strings.contains(msg, "foo.c"))
	testing.expect(t, len(msg) < 4000)
}
