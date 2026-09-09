// SPDX-License-Identifier: 0BSD
/*
Local offline docs: tldr, GNU info, --help, and language doc CLIs.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

tool_read_tldr :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	page, perr := json_arg_string(args_json, "page", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(page)
	platform, plerr := json_arg_string_optional(args_json, "platform", "", allocator)
	if plerr != "" {
		return "", plerr
	}
	defer delete(platform)
	max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
	if merr != "" {
		return "", merr
	}
	if max_chars <= 0 {
		max_chars = constants.MAX_MAN_PAGE_CHARS
	}
	pname := strings.trim_space(page)
	if !docs_safe_name(pname) {
		return "", strings.clone("invalid tldr page name", allocator)
	}
	exe, ok := find_on_path("tldr", context.temp_allocator)
	if !ok {
		return "", strings.clone("tldr not installed (install tealdeer or tldr and run tldr --update)", allocator)
	}
	argv: [dynamic]string
	argv.allocator = context.temp_allocator
	append(&argv, exe, "--color", "never")
	plat := strings.trim_space(platform)
	if len(plat) > 0 {
		if !docs_safe_name(plat) {
			return "", strings.clone("invalid tldr platform", allocator)
		}
		append(&argv, "--platform", plat)
	}
	append(&argv, pname)
	out, oerr := run_capture_argv(argv[:], allocator)
	if oerr != "" {
		return "", oerr
	}
	if len(strings.trim_space(out)) == 0 {
		delete(out)
		return "", strings.clone("tldr returned empty (try tldr --update)", allocator)
	}
	return docs_truncate(out, max_chars, allocator), ""
}

tool_read_info :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	node, nerr := json_arg_string(args_json, "node", allocator)
	if nerr != "" {
		return "", nerr
	}
	defer delete(node)
	max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
	if merr != "" {
		return "", merr
	}
	if max_chars <= 0 {
		max_chars = constants.MAX_MAN_PAGE_CHARS
	}
	topic := strings.trim_space(node)
	if len(topic) == 0 || !docs_safe_info_node(topic) {
		return "", strings.clone("invalid info node", allocator)
	}
	exe, ok := find_on_path("info", context.temp_allocator)
	if !ok {
		return "", strings.clone("info not installed (GNU texinfo)", allocator)
	}
	out, oerr := run_capture_argv([]string{exe, "-o", "-", topic}, allocator)
	if oerr != "" {
		return "", oerr
	}
	if len(strings.trim_space(out)) == 0 {
		delete(out)
		return "", fmt.aprintf("no info node for %s", topic, allocator = allocator)
	}
	return docs_truncate(out, max_chars, allocator), ""
}

tool_read_help :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	command, cerr := json_arg_string(args_json, "command", allocator)
	if cerr != "" {
		return "", cerr
	}
	defer delete(command)
	max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
	if merr != "" {
		return "", merr
	}
	if max_chars <= 0 {
		max_chars = constants.MAX_MAN_PAGE_CHARS
	}
	cmd := strings.trim_space(command)
	if !docs_safe_cmd_name(cmd) {
		return "", strings.clone("invalid help command name", allocator)
	}
	exe, ok := find_on_path(cmd, context.temp_allocator)
	if !ok {
		return "", fmt.aprintf("command not found on PATH: %s", cmd, allocator = allocator)
	}
	out, oerr := run_capture_argv([]string{exe, "--help"}, allocator)
	if oerr != "" {
		delete(out)
		out2, oerr2 := run_capture_argv([]string{exe, "-h"}, allocator)
		if oerr2 != "" {
			delete(out2)
			return "", oerr
		}
		out = out2
	}
	if len(strings.trim_space(out)) == 0 {
		delete(out)
		return "", fmt.aprintf("no help output from %s", cmd, allocator = allocator)
	}
	return docs_truncate(out, max_chars, allocator), ""
}

tool_lang_doc :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	lang, lerr := json_arg_string(args_json, "lang", allocator)
	if lerr != "" {
		return "", lerr
	}
	defer delete(lang)
	query, qerr := json_arg_string(args_json, "query", allocator)
	if qerr != "" {
		return "", qerr
	}
	defer delete(query)
	max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
	if merr != "" {
		return "", merr
	}
	if max_chars <= 0 {
		max_chars = constants.MAX_MAN_PAGE_CHARS
	}
	l := strings.to_lower(strings.trim_space(lang), context.temp_allocator)
	q := strings.trim_space(query)
	if len(q) == 0 || !docs_safe_lang_query(q) {
		return "", strings.clone("invalid lang_doc query", allocator)
	}
	out: string
	oerr: string
	switch l {
	case "go", "golang":
		exe, ok := find_on_path("go", context.temp_allocator)
		if !ok {
			return "", strings.clone("go not installed", allocator)
		}
		out, oerr = run_capture_argv([]string{exe, "doc", q}, allocator)
	case "python", "py", "python3":
		exe, ok := find_on_path("python3", context.temp_allocator)
		if !ok {
			exe, ok = find_on_path("python", context.temp_allocator)
		}
		if !ok {
			return "", strings.clone("python3 not installed", allocator)
		}
		out, oerr = run_capture_argv([]string{exe, "-m", "pydoc", q}, allocator)
	case "ruby", "rb":
		exe, ok := find_on_path("ri", context.temp_allocator)
		if !ok {
			return "", strings.clone("ri not installed", allocator)
		}
		out, oerr = run_capture_argv([]string{exe, "-T", q}, allocator)
	case "rust":
		out, oerr = lang_doc_rust(q, allocator)
	case:
		return "", strings.clone("lang must be go, python, ruby, or rust", allocator)
	}
	if oerr != "" {
		return "", oerr
	}
	if len(strings.trim_space(out)) == 0 {
		delete(out)
		return "", fmt.aprintf("no docs for %s %s", l, q, allocator = allocator)
	}
	return docs_truncate(out, max_chars, allocator), ""
}

@(private)
lang_doc_rust :: proc(query: string, allocator := context.allocator) -> (string, string) {
	exe, ok := find_on_path("rustup", context.temp_allocator)
	if !ok {
		return "", strings.clone("rustup not installed", allocator)
	}
	path_out, perr := run_capture_argv([]string{exe, "doc", "--path", query}, allocator)
	if perr != "" {
		return "", perr
	}
	path := strings.trim_space(path_out)
	delete(path_out)
	if len(path) == 0 {
		return "", strings.clone("rustup doc --path returned empty", allocator)
	}
	info, serr := os.stat(path, context.temp_allocator)
	if serr != nil {
		return "", fmt.aprintf("rust doc path missing: %s", path, allocator = allocator)
	}
	target := path
	if info.type == .Directory {
		joined, jerr := filepath.join({path, "index.html"}, context.temp_allocator)
		if jerr != nil {
			return "", strings.clone("rust doc index join failed", allocator)
		}
		target = joined
	}
	data, rerr := os.read_entire_file(target, allocator)
	if rerr != nil {
		return "", fmt.aprintf("failed to read rust docs at %s", target, allocator = allocator)
	}
	text := string(data)
	if html_looks_like(text) {
		plain := html_to_readable_text(text, allocator)
		delete(data)
		return plain, ""
	}
	return text, ""
}

@(private)
docs_truncate :: proc(owned: string, max_chars: int, allocator := context.allocator) -> string {
	if len(owned) <= max_chars {
		return owned
	}
	note := fmt.tprintf("\n\n[truncated at %d chars; raise max_chars]", max_chars)
	out := strings.concatenate({owned[:max_chars], note}, allocator)
	delete(owned)
	return out
}

@(private)
docs_safe_name :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 64 {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.':
		case:
			return false
		}
	}
	return true
}

@(private)
docs_safe_cmd_name :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 64 || strings.contains(s, "/") || strings.contains(s, "..") {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.', '+':
		case:
			return false
		}
	}
	return true
}

@(private)
docs_safe_info_node :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 128 {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.', ' ', '(', ')', ':':
		case:
			return false
		}
	}
	return true
}

@(private)
docs_safe_lang_query :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 128 {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.', ':', '/', '*', '(', ')':
		case:
			return false
		}
	}
	return true
}

find_on_path :: proc(name: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if len(name) == 0 || strings.contains(name, "/") {
		return "", false
	}
	for i in 0 ..< len(name) {
		if name[i] == 0 {
			return "", false
		}
	}
	raw, found := os.lookup_env("PATH", context.temp_allocator)
	if !found || len(raw) == 0 {
		raw = "/usr/bin:/bin"
	}
	copy := raw
	for part in strings.split_iterator(&copy, ":") {
		dir := strings.trim_space(part)
		if len(dir) == 0 {
			continue
		}
		cand, jerr := filepath.join({dir, name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if os.exists(cand) {
			return strings.clone(cand, allocator), true
		}
	}
	return "", false
}
