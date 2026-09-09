// SPDX-License-Identifier: 0BSD
/*
Fuzz and injection oracles for docs tools.
*/

package tools

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_fuzz_tldr_rejects_metachar_names :: proc(t: ^testing.T) {
	bad := []string{
		"tar;id",
		"tar|id",
		"tar`id`",
		"../etc/passwd",
		"tar/../../x",
		"tar $(id)",
		"tar\nid",
		"",
		" ",
		"a/b",
	}
	for b in bad {
		args := fmt.tprintf(`{"page":%q}`, b)
		out, err := tool_read_tldr(args)
		defer delete(out)
		defer delete(err)
		testing.expectf(t, err != "", "expected reject for %q", b)
		testing.expectf(t, !strings.contains(out, "uid="), "output leak for %q: %s", b, out)
	}
}

@(test)
test_fuzz_help_rejects_path_and_shell :: proc(t: ^testing.T) {
	bad := []string{
		"ls;id",
		"../bin/ls",
		"/bin/ls",
		"ls|id",
		"ls $(id)",
		"-c",
		"ls\nid",
	}
	for b in bad {
		args := fmt.tprintf(`{"command":%q}`, b)
		out, err := tool_read_help(args)
		defer delete(out)
		defer delete(err)
		testing.expectf(t, err != "", "expected reject for %q got out=%s", b, out)
	}
}

@(test)
test_fuzz_info_rejects_shell_nodes :: proc(t: ^testing.T) {
	bad := []string{
		"ls;id",
		"ls|id",
		"$(id)",
		"`id`",
		"ls\nid",
		"",
	}
	for b in bad {
		args := fmt.tprintf(`{"node":%q}`, b)
		out, err := tool_read_info(args)
		defer delete(out)
		defer delete(err)
		testing.expectf(t, err != "", "expected reject for %q", b)
	}
}

@(test)
test_fuzz_lang_doc_rejects_bad_query :: proc(t: ^testing.T) {
	testing.expect(t, docs_safe_lang_query("encoding/json"))
	testing.expect(t, docs_safe_lang_query("fmt.Println"))
	testing.expect(t, !docs_safe_lang_query("../secret"))
	testing.expect(t, !docs_safe_lang_query("../../etc/passwd"))
	testing.expect(t, !docs_safe_lang_query("/etc/passwd"))
	testing.expect(t, !docs_safe_lang_query("fmt;id"))
	testing.expect(t, !docs_safe_lang_query("$(id)"))

	out, err := tool_lang_doc(`{"lang":"go","query":"../x"}`)
	defer delete(out)
	defer delete(err)
	testing.expect(t, err != "")
	testing.expect(t, strings.contains(err, "invalid"))
}

@(test)
test_oracle_help_ls_still_works :: proc(t: ^testing.T) {
	out, err := tool_read_help(`{"command":"ls"}`)
	defer delete(out)
	defer delete(err)
	testing.expect(t, err == "")
	testing.expect(t, len(out) > 0)
}

@(test)
test_oracle_info_allows_parenthetical_nodes :: proc(t: ^testing.T) {
	// Valid info node shape used by texinfo manuals.
	testing.expect(t, docs_safe_info_node("(coreutils)ls invocation"))
	testing.expect(t, !docs_safe_info_node("(coreutils);id"))
}
