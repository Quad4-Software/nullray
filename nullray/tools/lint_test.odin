// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_lint_rule_for_path :: proc(t: ^testing.T) {
	rules := []Lint_Rule{
		{glob = "*.odin", cmd = "odin check {path} -file"},
		{glob = "*.go", cmd = "gofmt -e {path}"},
	}
	r, ok := lint_rule_for_path("nullray/app/foo.odin", rules)
	testing.expect(t, ok)
	testing.expect_value(t, r.cmd, "odin check {path} -file")
	_, gok := lint_rule_for_path("readme.md", rules)
	testing.expect(t, !gok)
}

@(test)
test_lint_expand_cmd_quotes_path :: proc(t: ^testing.T) {
	out := lint_expand_cmd("odin check {path} -file", "nullray/app/foo.odin")
	testing.expect(t, strings.contains(out, "'nullray/app/foo.odin'"))
	testing.expect(t, !strings.contains(out, "{path}"))
}

@(test)
test_lint_looks_like_error :: proc(t: ^testing.T) {
	testing.expect(t, lint_looks_like_error("foo.odin(1:1) Error: undeclared"))
	testing.expect(t, lint_looks_like_error("a.ts:1:1: error TS123"))
	testing.expect(t, !lint_looks_like_error("ok\nall good"))
}

@(test)
test_lint_disabled_env :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_LINT, "0")
	defer os.unset_env(constants.ENV_LINT)
	testing.expect(t, !lint_enabled())
	testing.expect_value(t, lint_after_write("x.odin"), "")
}
