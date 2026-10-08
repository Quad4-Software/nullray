// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package skills

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_skills_save_and_load :: proc(t: ^testing.T) {
	path, err := skills_save("unit-learn-skill", "Unit Learn", "short desc", "Do the thing carefully.\nStep 2.\n", []string{"**/*.odin"})
	testing.expect_value(t, err, "")
	defer {
		_ = skills_delete("unit-learn-skill")
		delete(path)
	}
	testing.expect(t, strings.contains(path, "unit-learn-skill"))
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, rerr == nil)
	s := string(data)
	testing.expect(t, strings.contains(s, "name:"))
	testing.expect(t, strings.contains(s, "Do the thing"))
}
