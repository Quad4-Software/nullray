// SPDX-License-Identifier: 0BSD
package secure

import "base:runtime"
import "core:path/filepath"
import "core:strings"

audit_owasp :: proc(workspace: string, allocator := context.allocator) -> string {
	w: Finding_Writer
	writer_init(&w, allocator)
	walk_files(workspace, workspace, &w, owasp_visit, allocator)
	return writer_text(&w)
}

owasp_visit :: proc(root, path: string, user: rawptr, allocator: runtime.Allocator) {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".odin", ".go", ".py", ".js", ".ts", ".tsx", ".jsx", ".java", ".rs", ".rb", ".php", ".cs":
	case:
		return
	}
	text, ok := read_small_file(path, allocator)
	if !ok {
		return
	}
	defer delete(text)
	w := cast(^Finding_Writer)user
	rel := relative_path(root, path)
	for line, index in strings.split_lines(text, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || is_line_comment(trimmed) {
			continue
		}
		lower := strings.to_lower(trimmed, context.temp_allocator)
		owasp_scan_line(w, rel, index + 1, ext, lower, trimmed)
	}
}

is_line_comment :: proc(trimmed: string) -> bool {
	return strings.has_prefix(trimmed, "//") ||
		strings.has_prefix(trimmed, "#") ||
		strings.has_prefix(trimmed, "/*") ||
		strings.has_prefix(trimmed, "*") ||
		strings.has_prefix(trimmed, "--")
}

owasp_scan_line :: proc(w: ^Finding_Writer, rel: string, line: int, ext, lower, trimmed: string) {
	owasp_scan_secrets(w, rel, line, lower, trimmed)
	owasp_scan_injection(w, rel, line, ext, lower)
	owasp_scan_xss(w, rel, line, lower)
	owasp_scan_path(w, rel, line, lower)
}

// Needles are assembled so this file does not match itself.
owasp_scan_secrets :: proc(w: ^Finding_Writer, rel: string, line: int, lower, trimmed: string) {
	pem := strings.concatenate({"-----begin ", "private key-----"}, context.temp_allocator)
	pem_rsa := strings.concatenate({"-----begin rsa ", "private key-----"}, context.temp_allocator)
	pem_ssh := strings.concatenate({"-----begin openssh ", "private key-----"}, context.temp_allocator)
	if strings.contains(lower, pem) || strings.contains(lower, pem_rsa) || strings.contains(lower, pem_ssh) {
		finding(w, "high", "owasp", rel, line, "embedded private key material")
		return
	}
	akia := strings.concatenate({"AK", "IA"}, context.temp_allocator)
	if strings.contains(trimmed, akia) {
		rest := trimmed[strings.index(trimmed, akia) + 4:]
		if len(rest) >= 16 && is_alnum_run(rest, 16) {
			finding(w, "high", "owasp", rel, line, "possible AWS access key id")
		}
	}
	parts := [][2]string{
		{"sk-", "or-v1-"},
		{"sk-", "ant-"},
		{"gh", "p_"},
		{"gh", "o_"},
		{"xo", "xb-"},
		{"xo", "xp-"},
	}
	for p in parts {
		needle := strings.concatenate({p[0], p[1]}, context.temp_allocator)
		if strings.contains(trimmed, needle) {
			finding(w, "high", "owasp", rel, line, "possible API or bot token in source")
			break
		}
	}
	if has_quoted_secret_assign(lower) {
		finding(w, "warn", "owasp", rel, line, "possible hardcoded credential")
	}
}

is_alnum_run :: proc(s: string, n: int) -> bool {
	if len(s) < n {
		return false
	}
	for i in 0 ..< n {
		c := s[i]
		ok := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
		if !ok {
			return false
		}
	}
	return true
}

has_quoted_secret_assign :: proc(lower: string) -> bool {
	keys := []string{
		"password", "passwd", "secret", "api_key", "apikey", "api-key",
		"access_token", "auth_token", "private_key", "client_secret",
	}
	for key in keys {
		if secret_key_has_quoted_value(lower, key) {
			return true
		}
	}
	return false
}

secret_key_has_quoted_value :: proc(lower, key: string) -> bool {
	start := 0
	for start < len(lower) {
		rel := strings.index(lower[start:], key)
		if rel < 0 {
			return false
		}
		abs := start + rel
		if abs > 0 {
			c := lower[abs - 1]
			if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' {
				start = abs + len(key)
				continue
			}
		}
		after := lower[abs + len(key):]
		quote: u8
		rest: string
		if strings.has_prefix(after, ` = "`) {
			quote = '"'
			rest = after[4:]
		} else if strings.has_prefix(after, ` = '`) {
			quote = '\''
			rest = after[4:]
		} else if strings.has_prefix(after, `="`) {
			quote = '"'
			rest = after[2:]
		} else if strings.has_prefix(after, `='`) {
			quote = '\''
			rest = after[2:]
		} else if strings.has_prefix(after, `: "`) {
			quote = '"'
			rest = after[3:]
		} else if strings.has_prefix(after, `: '`) {
			quote = '\''
			rest = after[3:]
		} else if strings.has_prefix(after, `:"`) {
			quote = '"'
			rest = after[2:]
		} else if strings.has_prefix(after, `:'`) {
			quote = '\''
			rest = after[2:]
		} else if strings.has_prefix(after, ` := "`) {
			quote = '"'
			rest = after[5:]
		} else if strings.has_prefix(after, ` := '`) {
			quote = '\''
			rest = after[5:]
		}
		if quote != 0 {
			close := strings.index_byte(rest, quote)
			if close > 0 {
				return true
			}
		}
		start = abs + len(key)
	}
	return false
}

owasp_scan_injection :: proc(w: ^Finding_Writer, rel: string, line: int, ext, lower: string) {
	switch ext {
	case ".py":
		if strings.contains(lower, "shell=true") ||
		   strings.contains(lower, "os.system(") ||
		   (strings.contains(lower, "subprocess.call(") && strings.contains(lower, "shell")) ||
		   strings.contains(lower, "popen(") {
			finding(w, "high", "owasp", rel, line, "possible command injection via shell")
		}
		if strings.contains(lower, "eval(") || strings.contains(lower, "exec(") {
			finding(w, "high", "owasp", rel, line, "dynamic code execution")
		}
		if strings.contains(lower, "pickle.loads(") || strings.contains(lower, "yaml.load(") {
			finding(w, "warn", "owasp", rel, line, "unsafe deserializer")
		}
	case ".js", ".ts", ".tsx", ".jsx":
		if strings.contains(lower, "child_process") &&
		   (strings.contains(lower, "exec(") || strings.contains(lower, "execsync(")) {
			finding(w, "high", "owasp", rel, line, "possible command injection via child_process")
		}
		if strings.contains(lower, "eval(") || strings.contains(lower, "new function(") {
			finding(w, "high", "owasp", rel, line, "dynamic code execution")
		}
	case ".go":
		if strings.contains(lower, "exec.command(") &&
		   (strings.contains(lower, `"sh"`) ||
			strings.contains(lower, `"bash"`) ||
			strings.contains(lower, `"/bin/sh"`) ||
			strings.contains(lower, `"-c"`)) {
			finding(w, "high", "owasp", rel, line, "possible command injection via shell -c")
		}
	case ".php":
		if strings.contains(lower, "shell_exec(") ||
		   strings.contains(lower, "passthru(") ||
		   strings.contains(lower, "system(") ||
		   strings.contains(lower, "eval(") {
			finding(w, "high", "owasp", rel, line, "possible command or code injection")
		}
	}

	if looks_like_sql_concat(lower) {
		finding(w, "high", "owasp", rel, line, "possible SQL injection via string concat")
	}
}

looks_like_sql_concat :: proc(lower: string) -> bool {
	// Require a SQL keyword inside quotes so detector source and expectf strings do not match.
	has_sql_lit := strings.contains(lower, `"select `) ||
		strings.contains(lower, `'select `) ||
		strings.contains(lower, `"insert into`) ||
		strings.contains(lower, `'insert into`) ||
		strings.contains(lower, `"delete from`) ||
		strings.contains(lower, `'delete from`) ||
		strings.contains(lower, `"update `) ||
		strings.contains(lower, `'update `)
	if !has_sql_lit {
		return false
	}
	return strings.contains(lower, " + ") ||
		strings.contains(lower, "+ ") ||
		strings.contains(lower, " +") ||
		strings.contains(lower, ".format(") ||
		strings.contains(lower, "f\"") ||
		strings.contains(lower, "f'") ||
		strings.contains(lower, "${")
}

owasp_scan_xss :: proc(w: ^Finding_Writer, rel: string, line: int, lower: string) {
	inner := strings.concatenate({"inner", "html"}, context.temp_allocator)
	danger := strings.concatenate({"dangerouslyset", "inner", "html"}, context.temp_allocator)
	doc_write := strings.concatenate({"document.", "write("}, context.temp_allocator)
	if strings.contains(lower, inner) ||
	   strings.contains(lower, danger) ||
	   strings.contains(lower, doc_write) {
		finding(w, "warn", "owasp", rel, line, "possible XSS sink")
	}
}

owasp_scan_path :: proc(w: ^Finding_Writer, rel: string, line: int, lower: string) {
	if !strings.contains(lower, "../") && !strings.contains(lower, "..\\") {
		return
	}
	opens := strings.contains(lower, "open(") ||
		strings.contains(lower, "readfile") ||
		strings.contains(lower, "read_file") ||
		strings.contains(lower, "os.open") ||
		strings.contains(lower, "ioutil.") ||
		strings.contains(lower, "sendfile") ||
		strings.contains(lower, "filepath.join") ||
		strings.contains(lower, "path.join") ||
		strings.contains(lower, "os.path.join")
	if opens {
		finding(w, "warn", "owasp", rel, line, "possible path traversal in file access")
	}
}
