// SPDX-License-Identifier: 0BSD
package structure

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_policy_defaults_and_override :: proc(t: ^testing.T) {
	root := "/tmp/nullray-structure-policy-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	policy, err := load_policy(root)
	defer delete(err)
	testing.expect(t, len(err) == 0)
	testing.expect_value(t, policy.max_file_lines, constants.DEFAULT_MAX_FILE_LINES)

	dir, derr := filepath.join({root, ".nullray"}, context.temp_allocator)
	testing.expect(t, derr == nil)
	testing.expect(t, os.make_directory_all(dir) == nil)
	path, perr := filepath.join({dir, "policy.json"}, context.temp_allocator)
	testing.expect(t, perr == nil)
	testing.expect(t, os.write_entire_file(path, `{"max_file_lines":12,"warn_lines":8}`) == nil)

	policy, err = load_policy(root)
	defer delete(err)
	testing.expect(t, len(err) == 0)
	testing.expect_value(t, policy.max_file_lines, 12)
	testing.expect_value(t, policy.warn_file_lines, 8)
}

@(test)
test_growth_gate_allows_oversized_reduction :: proc(t: ^testing.T) {
	root := "/tmp/nullray-structure-growth-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	dir, _ := filepath.join({root, ".nullray"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(dir) == nil)
	path, _ := filepath.join({dir, "policy.json"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, `{"max_file_lines":3,"warn_lines":2}`) == nil)

	blocked := growth_error(root, "a.odin", "a\nb\nc", "a\nb\nc\nd", false)
	defer delete(blocked)
	testing.expect(t, len(blocked) > 0)

	allowed := growth_error(root, "a.odin", "a\nb\nc\nd", "a\nb\nc", false)
	defer delete(allowed)
	testing.expect(t, len(allowed) == 0)
}

@(test)
test_audit_reports_odin_godfile_skips_vendor :: proc(t: ^testing.T) {
	root := "/tmp/nullray-structure-audit-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	dir, _ := filepath.join({root, ".nullray"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(dir) == nil)
	policy_path, _ := filepath.join({dir, "policy.json"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(policy_path, `{"max_file_lines":3,"warn_lines":2}`) == nil)

	src, _ := filepath.join({root, "fat.odin"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(src, "a\nb\nc\nd\n") == nil)

	vendor, _ := filepath.join({root, "vendor", "skip.odin"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(filepath.dir(vendor)) == nil)
	testing.expect(t, os.write_entire_file(vendor, "a\nb\nc\nd\ne\n") == nil)

	other, _ := filepath.join({root, "notes.md"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(other, "a\nb\nc\nd\ne\nf\n") == nil)

	report, err := audit(root)
	defer delete(report)
	defer delete(err)
	testing.expect(t, len(err) == 0)
	testing.expect(t, strings.contains(report, "godfile|fat.odin|"))
	testing.expect(t, !strings.contains(report, "vendor"))
	testing.expect(t, !strings.contains(report, "notes.md"))
	testing.expect(t, report_has_godfiles(report))
}

@(test)
test_repo_odin_has_no_godfiles :: proc(t: ^testing.T) {
	root := find_repo_root()
	testing.expect(t, len(root) > 0)
	if len(root) == 0 {
		return
	}
	defer delete(root)

	report, err := audit(root)
	defer delete(report)
	defer delete(err)
	testing.expect(t, len(err) == 0)
	testing.expect(t, !report_has_godfiles(report))
}
