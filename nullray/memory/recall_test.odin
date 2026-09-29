// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package memory

import "core:strings"
import "core:testing"

@(test)
test_recall_glob_basename :: proc(t: ^testing.T) {
	testing.expect(t, recall_glob_match("Makefile", "src/tools/Makefile"))
	testing.expect(t, recall_glob_match("Makefile", "Makefile"))
	testing.expect(t, !recall_glob_match("Makefile", "src/tools/maker.sh"))
}

@(test)
test_recall_glob_star :: proc(t: ^testing.T) {
	testing.expect(t, recall_glob_match("*.odin", "nullray/app/app.odin"))
	testing.expect(t, !recall_glob_match("*.odin", "nullray/app/app.py"))
}

@(test)
test_recall_glob_double_star :: proc(t: ^testing.T) {
	testing.expect(t, recall_glob_match("nullray/provider/**", "nullray/provider/deep/x.odin"))
	testing.expect(t, recall_glob_match("**/hooks/**", "a/hooks/b/c.odin"))
	testing.expect(t, !recall_glob_match("nullray/provider/**", "other/x.odin"))
}

@(test)
test_recall_extract_args :: proc(t: ^testing.T) {
	path, cmd := recall_extract_args(`{"path":"src/x.odin","command":"make test"}`)
	testing.expect_value(t, path, "src/x.odin")
	testing.expect_value(t, cmd, "make test")
	p2, c2 := recall_extract_args(`not json`)
	testing.expect_value(t, p2, "")
	testing.expect_value(t, c2, "")
	p3, _ := recall_extract_args(`{"file":"/tmp/y.txt"}`)
	testing.expect_value(t, p3, "/tmp/y.txt")
}

@(test)
test_recall_for_tool_scoped :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	m1, e1 := Put("recall.path.Makefile", "run make test after editing targets")
	defer delete(m1)
	defer delete(e1)
	m2, e2 := Put("recall.cmd.git push", "never force push")
	defer delete(m2)
	defer delete(e2)
	m3, e3 := Put("recall.tool.read_file", "prefer offset+limit over whole file")
	defer delete(m3)
	defer delete(e3)
	m4, e4 := Put("pref.editor", "not a recall key")
	defer delete(m4)
	defer delete(e4)

	out := recall_for_tool("edit_file", `{"path":"x/Makefile"}`, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "make test"))
	testing.expect(t, !strings.contains(out, "force push"))
	testing.expect(t, !strings.contains(out, "prefer offset"))
	testing.expect(t, !strings.contains(out, "not a recall"))

	out2 := recall_for_tool("run_shell", `{"command":"git push origin main"}`, context.allocator)
	defer delete(out2)
	testing.expect(t, strings.contains(out2, "force push"))

	out3 := recall_for_tool("read_file", `{"path":"z.txt"}`, context.allocator)
	defer delete(out3)
	testing.expect(t, strings.contains(out3, "prefer offset"))

	out4 := recall_for_tool("edit_file", `{"path":"src/main.c"}`, context.allocator)
	defer delete(out4)
	testing.expect_value(t, out4, "")
}

@(test)
test_recall_path_key_matches_shell_command :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	m, e := Put("recall.path.secret.conf", "chmod 600 after edits")
	defer delete(m)
	defer delete(e)

	out := recall_for_tool("run_shell", `{"command":"cat > secret.conf <<'X'\nkey=1\nX"}`, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "chmod 600"))

	out2 := recall_for_tool("run_shell", `{"command":"cat > other.conf <<'X'\nx=1\nX"}`, context.allocator)
	defer delete(out2)
	testing.expect_value(t, out2, "")
}
