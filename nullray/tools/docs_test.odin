// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_read_tldr_when_present :: proc(t: ^testing.T) {
	_, has := find_on_path("tldr", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_read_tldr(`{"page":"tar"}`, context.allocator)
	defer delete(out)
	if err != "" {
		// Soft-ok when cache missing
		testing.expect(t, strings.contains(err, "tldr") || strings.contains(err, "cache") || strings.contains(err, "failed"))
		return
	}
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "tar"))
}

@(test)
test_read_info_ls :: proc(t: ^testing.T) {
	_, has := find_on_path("info", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_read_info(`{"node":"ls"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "ls"))
}

@(test)
test_read_help_ls :: proc(t: ^testing.T) {
	out, err := tool_read_help(`{"command":"ls"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "usage") || strings.contains(out, "ls"))
}

@(test)
test_read_help_rejects_path :: proc(t: ^testing.T) {
	out, err := tool_read_help(`{"command":"../bin/ls"}`, context.allocator)
	defer delete(out)
	defer delete(err)
	testing.expect(t, err != "")
	testing.expect(t, strings.contains(err, "invalid"))
}

@(test)
test_lang_doc_go :: proc(t: ^testing.T) {
	_, has := find_on_path("go", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_lang_doc(`{"lang":"go","query":"fmt.Println"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "Println"))
}

@(test)
test_lang_doc_python :: proc(t: ^testing.T) {
	_, has := find_on_path("python3", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_lang_doc(`{"lang":"python","query":"os.path.join"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "join"))
}

// Regression: the apropos keyword went through /bin/sh -c so $(...) and
// friends executed; argv exec must treat them as literal search text.
@(test)
test_apropos_no_shell_injection :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	_, has := find_on_path("apropos", context.temp_allocator)
	if !has {
		return
	}
	marker := "/tmp/nullray-apropos-pwned"
	_ = os.remove(marker)
	defer os.remove(marker)
	out, err := tool_apropos(`{"keyword":"x$(touch /tmp/nullray-apropos-pwned)x"}`, context.allocator)
	defer delete(out)
	defer delete(err)
	testing.expectf(t, !os.exists(marker), "apropos keyword reached a shell")
}

@(test)
test_apropos_real_keyword_when_present :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	_, has := find_on_path("apropos", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_apropos(`{"keyword":"printf"}`, context.allocator)
	defer delete(out)
	defer delete(err)
	if err != "" {
		// apropos db may be absent on minimal systems
		testing.expect(t, strings.contains(err, "apropos") || strings.contains(err, "failed"))
		return
	}
	testing.expect(t, strings.contains(out, "printf") || strings.contains(out, "no apropos matches"))
}

@(test)
test_lang_doc_rust_when_present :: proc(t: ^testing.T) {
	_, has := find_on_path("rustup", context.temp_allocator)
	if !has {
		return
	}
	out, err := tool_lang_doc(`{"lang":"rust","query":"std","max_chars":"4000"}`, context.allocator)
	defer delete(out)
	if err != "" {
		// rustup on PATH does not mean std docs are installed or readable here
		delete(err)
		return
	}
	testing.expect(t, len(out) > 0)
	testing.expect(t, !strings.contains(out, "<script"))
}
