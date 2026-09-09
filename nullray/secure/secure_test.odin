// SPDX-License-Identifier: 0BSD
package secure

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_actions_and_dockerfile_findings :: proc(t: ^testing.T) {
	root := "/tmp/nullray-secure-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	workflows, _ := filepath.join({root, ".github", "workflows"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(workflows) == nil)
	workflow, _ := filepath.join({workflows, "ci.yml"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(workflow, "on:\n  pull_request_target:\nsteps:\n  - uses: actions/checkout@v4\n") == nil)
	dockerfile, _ := filepath.join({root, "Dockerfile"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(dockerfile, "FROM alpine:latest\nRUN curl x | bash\n") == nil)

	actions := audit_actions(root)
	defer delete(actions)
	testing.expect(t, strings.contains(actions, "high|actions"))
	testing.expect(t, strings.contains(actions, "warn|actions"))

	docker := audit_dockerfile(root)
	defer delete(docker)
	testing.expect(t, strings.contains(docker, "high|dockerfile"))
	testing.expect(t, strings.contains(docker, "curl output"))
	testing.expect(t, strings.contains(docker, "no non-root USER"))
}

@(test)
test_owasp_vuln_patterns :: proc(t: ^testing.T) {
	root := "/tmp/nullray-owasp-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	py, _ := filepath.join({root, "app.py"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(py, strings.concatenate({
		"password = \"hunter2\"\n",
		"os.system(\"rm \" + user)\n",
		"cur.execute(\"SELECT * FROM u WHERE id=\" + id)\n",
		"data = open(\"../\" + name).read()\n",
		"obj = pickle.loads(blob)\n",
	}, context.temp_allocator)) == nil)

	js, _ := filepath.join({root, "ui.js"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(js, "el.innerHTML = userInput\n") == nil)

	go_src, _ := filepath.join({root, "run.go"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(go_src, "exec.Command(\"sh\", \"-c\", cmd)\n") == nil)

	tok, _ := filepath.join({root, "keys.ts"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(tok, "const k = \"sk-or-v1-deadbeef\"\n") == nil)

	clean, _ := filepath.join({root, "ok.py"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(clean, "# password = \"example\"\nx = 1\n") == nil)

	out := audit_owasp(root)
	defer delete(out)
	testing.expect(t, strings.contains(out, "possible hardcoded credential"))
	testing.expect(t, strings.contains(out, "possible command injection via shell"))
	testing.expect(t, strings.contains(out, "possible SQL injection via string concat"))
	testing.expect(t, strings.contains(out, "possible path traversal"))
	testing.expect(t, strings.contains(out, "unsafe deserializer"))
	testing.expect(t, strings.contains(out, "possible XSS sink"))
	testing.expect(t, strings.contains(out, "possible command injection via shell -c"))
	testing.expect(t, strings.contains(out, "possible API or bot token"))
	testing.expect(t, !strings.contains(out, "ok.py"))
}

@(test)
test_deps_missing_lock :: proc(t: ^testing.T) {
	root := "/tmp/nullray-deps-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	manifest, _ := filepath.join({root, "package.json"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(manifest, "{}\n") == nil)
	out := audit_deps(root)
	defer delete(out)
	testing.expect(t, strings.contains(out, "warn|deps|package.json"))
}

@(test)
test_secret_assign_negatives :: proc(t: ^testing.T) {
	testing.expect(t, !has_quoted_secret_assign(`"api_key=",`))
	testing.expect(t, !has_quoted_secret_assign(`"secret=",`))
	testing.expect(t, has_quoted_secret_assign(`password = "hunter2"`))
	testing.expect(t, has_quoted_secret_assign(`api_key = "x"`))
	testing.expect(t, !has_quoted_secret_assign(`ENV_API_KEY :: "NULLRAY_API_KEY"`))
}
