// SPDX-License-Identifier: 0BSD
/*
Artifact store round-trip tests.
*/

package store

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(test)
test_artifact_roundtrip :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-artifact-test-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)

	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	body := strings.repeat("line\n", 100, context.temp_allocator)
	id, ok := artifact_store(body)
	testing.expect(t, ok)
	testing.expect(t, len(id) > 0)
	defer delete(id)

	got, err := artifact_read(id)
	testing.expect_value(t, err, "")
	testing.expect_value(t, got, body)
	delete(got)

	hits, gerr := artifact_grep(id, "line")
	testing.expect_value(t, gerr, "")
	testing.expect(t, strings.contains(hits, "1:line"))
	delete(hits)

	testing.expect(t, !artifact_id_ok("../etc"))
	_, bad := artifact_read("../etc")
	testing.expect(t, len(bad) > 0)
	delete(bad)
}
