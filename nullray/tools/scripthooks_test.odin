// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

@(private)
script_test_write :: proc(dir, name, body: string, exec: bool) {
	p, perr := filepath.join({dir, name}, context.temp_allocator)
	testing.expect(nil, perr == nil)
	if perr != nil {
		return
	}
	_ = os.write_entire_file(p, transmute([]u8)body)
	when ODIN_OS != .Windows {
		if exec {
			_ = os.chmod(p, os.perm(0o755))
		}
	}
}

@(test)
test_script_tools_scan_registers :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	root := "/tmp/nullray-scripttools-scan"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	script_test_write(root, "hello.sh", "#!/bin/sh\ncat\n", true)
	script_test_write(root, "hello.md", "Says hi.\n\nSecond paragraph.\n", false)
	script_test_write(root, "hello.schema.json", `{"type":"object","properties":{"who":{"type":"string"}}}`, false)
	script_test_write(root, "meta_read.sh", "#!/bin/sh\ntrue\n", true)
	script_test_write(root, "meta_read.meta", "kind=read\n", false)
	// Non-executable script and a builtin-name shadow attempt must skip.
	script_test_write(root, "nonexec.sh", "#!/bin/sh\ntrue\n", false)
	script_test_write(root, "run_shell.sh", "#!/bin/sh\ntrue\n", true)
	script_test_write(root, "rawtool", "#!/bin/sh\ncat\n", true)

	r: Registry
	r.tools = make([dynamic]Tool)
	r.script_tools = make([dynamic]^Script_Tool)
	defer {
		script_tools_destroy(&r)
		delete(r.tools)
	}
	// Stand-in builtin: scripts must not replace existing registrations.
	registry_register(&r, Tool{name = "run_shell", kind = .Shell})
	script_tools_scan_dir(&r, root)

	hello, found := registry_find(&r, "hello")
	testing.expect(t, found)
	if found {
		testing.expect_value(t, hello.description, "Says hi.")
		testing.expect(t, hello.kind == .Shell)
		testing.expect(t, strings.contains(hello.schema_json, `"who"`))
	}
	mr, mfound := registry_find(&r, "meta_read")
	testing.expect(t, mfound)
	if mfound {
		testing.expect(t, mr.kind == .Read)
	}
	_, ne := registry_find(&r, "nonexec")
	testing.expect(t, !ne)
	raw, rfound := registry_find(&r, "rawtool")
	testing.expect(t, rfound)
	if rfound {
		testing.expect(t, raw.run_named != nil)
	}
	// The builtin stays the plain proc, not the script binding.
	rs, _ := registry_find(&r, "run_shell")
	testing.expect(t, rs.run_named == nil && rs.user == nil)
}

@(test)
test_script_tool_exec_stdout_and_failure :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	root := "/tmp/nullray-scripttools-exec"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	script_test_write(root, "echo.sh", "#!/bin/sh\ncat\n", true)
	script_test_write(root, "fail.sh", "#!/bin/sh\necho bad-things >&2\nexit 3\n", true)

	r: Registry
	r.tools = make([dynamic]Tool)
	r.script_tools = make([dynamic]^Script_Tool)
	defer {
		script_tools_destroy(&r)
		delete(r.tools)
	}
	script_tools_scan_dir(&r, root)

	echo_tool, found := registry_find(&r, "echo")
	testing.expect(t, found)
	if found {
		res, err := run(&r, "echo", `{"input":"abc123"}`, "edit", context.allocator)
		defer delete(res)
		defer delete(err)
		testing.expectf(t, err == "", "err=%s", err)
		testing.expectf(t, strings.contains(res, "abc123"), "res=%q", res)
	}
	fail_tool, ffound := registry_find(&r, "fail")
	testing.expect(t, ffound)
	if ffound {
		res2, err2 := run(&r, "fail", "{}", "edit", context.allocator)
		defer delete(res2)
		defer delete(err2)
		testing.expectf(t, strings.contains(res2, "exit_code=3"), "res2=%q err2=%q", res2, err2)
		testing.expectf(t, strings.contains(res2, "stderr:"), "res2=%q", res2)
		testing.expectf(t, strings.contains(res2, "bad-things"), "res2=%q", res2)
	}
}

// Regression: a detached grandchild holding the pipe write end must not
// wedge the post-exit drain, and the real exit code must survive.
@(test)
test_script_tool_capture_detached_grandchild :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	res, err := script_tool_run_capture(
		[]string{"/bin/sh", "-c", "sleep 15 & exit 7"},
		".",
		"",
		nil,
		context.allocator,
	)
	defer delete(res)
	defer delete(err)
	testing.expectf(t, strings.contains(res, "exit_code=7"), "res=%q err=%q", res, err)
	testing.expectf(t, time.since(start) < 10 * time.Second, "detached grandchild wedged the drain")
}

@(private)
Flood_Writer :: struct {
	w:    ^os.File,
	stop: ^bool,
}

@(private)
flood_writer_proc :: proc(data: rawptr) {
	fw := cast(^Flood_Writer)data
	payload := transmute([]u8)string("flood-line\n")
	for !sync.atomic_load(fw.stop) {
		n, werr := os.write(fw.w, payload)
		if n <= 0 || werr != nil {
			return
		}
	}
}

// Regression: a writer that keeps the pipe full used to keep script_drain
// inside its has_data loop forever, starving the outer timeout check.
@(test)
test_script_drain_bounds_flood :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	r, w, perr := os.pipe()
	testing.expect(t, perr == nil)
	defer os.close(r)
	defer os.close(w)
	stop := false
	fw := Flood_Writer{w = w, stop = &stop}
	wth := thread.create_and_start_with_data(&fw, flood_writer_proc)
	testing.expect(t, wth != nil)
	// Let the writer get the pipe full before the drain starts.
	time.sleep(50 * time.Millisecond)

	buf: [4096]u8
	b: [dynamic]u8
	b.allocator = context.temp_allocator
	start := time.now()
	eof := script_drain(r, &b, buf[:], 1 << 20)
	elapsed := time.since(start)
	// Not EOF (writer still alive); the call returned inside the byte
	// budget instead of chasing the flood.
	testing.expect(t, !eof)
	testing.expect(t, len(b) > 0)
	testing.expectf(t, elapsed < 5 * time.Second, "drain ran %v", elapsed)

	sync.atomic_store(&stop, true)
	// Free a writer blocked on a full pipe so it can observe stop.
	_ = script_drain(r, &b, buf[:], 1 << 20)
	if wth != nil {
		thread.join(wth)
		thread.destroy(wth)
	}
}

@(test)
test_script_tool_name_ok_rules :: proc(t: ^testing.T) {
	testing.expect(t, script_tool_name_ok("hello"))
	testing.expect(t, script_tool_name_ok("my-tool_1"))
	testing.expect(t, !script_tool_name_ok(""))
	testing.expect(t, !script_tool_name_ok("-x"))
	testing.expect(t, !script_tool_name_ok("a.b"))
	testing.expect(t, !script_tool_name_ok("a/b"))
}
