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
