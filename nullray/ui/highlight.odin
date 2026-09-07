// SPDX-License-Identifier: 0BSD
/*
Simple keyword highlighter for common programming languages.
*/

package ui

import "core:strings"
import "core:unicode"

Hl_Kind :: enum {
	Normal,
	Keyword,
	String,
	Comment,
	Number,
	Type,
	Ident,
}

Hl_Span :: struct {
	start, end: int,
	kind:       Hl_Kind,
}

hl_color :: proc(kind: Hl_Kind, theme: Theme) -> Color {
	switch kind {
	case .Normal:
		return theme.fg
	case .Keyword:
		return theme.accent
	case .String:
		return theme.ok
	case .Comment:
		return theme.muted
	case .Number:
		return theme.warn
	case .Type:
		return theme.title
	case .Ident:
		return theme.user_fg
	}
	return theme.fg
}

highlight_line :: proc(lang, line: string, allocator := context.temp_allocator) -> []Hl_Span {
	n := len(line)
	if n == 0 {
		spans: [dynamic]Hl_Span
		spans.allocator = allocator
		append(&spans, Hl_Span{start = 0, end = 0, kind = .Normal})
		return spans[:]
	}

	kinds := make([]Hl_Kind, n, allocator)
	for i in 0 ..< n {
		kinds[i] = .Normal
	}

	normalized := strings.to_lower(lang, context.temp_allocator)
	hl_apply_strings(line, kinds)
	hl_apply_comments(normalized, line, kinds)
	hl_apply_numbers(line, kinds)
	hl_apply_keywords(normalized, line, kinds)

	spans: [dynamic]Hl_Span
	spans.allocator = allocator
	cur := kinds[0]
	start := 0
	for i in 1 ..< n {
		if kinds[i] != cur {
			append(&spans, Hl_Span{start = start, end = i, kind = cur})
			cur = kinds[i]
			start = i
		}
	}
	append(&spans, Hl_Span{start = start, end = n, kind = cur})
	return spans[:]
}

@(private)
hl_apply_comments :: proc(lang: string, line: string, kinds: []Hl_Kind) {
	comment_start := -1
	switch lang {
	case "python", "py", "sh", "bash":
		for i in 0 ..< len(line) {
			if line[i] == '#' && !hl_in_string_at(kinds, i) {
				comment_start = i
				break
			}
		}
	case "odin", "go", "javascript", "js", "typescript", "ts", "c", "cpp", "rust":
		idx := strings.index(line, "//")
		if idx >= 0 && !hl_in_string_at(kinds, idx) {
			comment_start = idx
		}
	case:
		return
	}
	if comment_start >= 0 {
		for i in comment_start ..< len(line) {
			kinds[i] = .Comment
		}
	}
}

@(private)
hl_in_string_at :: proc(kinds: []Hl_Kind, i: int) -> bool {
	if i < 0 || i >= len(kinds) {
		return false
	}
	return kinds[i] == .String
}

@(private)
hl_apply_strings :: proc(line: string, kinds: []Hl_Kind) {
	in_str := false
	quote: u8
	i := 0
	for i < len(line) {
		if kinds[i] == .Comment {
			i += 1
			continue
		}
		c := line[i]
		if in_str {
			kinds[i] = .String
			if c == '\\' && i + 1 < len(line) {
				kinds[i + 1] = .String
				i += 2
				continue
			}
			if c == quote {
				in_str = false
			}
			i += 1
			continue
		}
		if c == '"' || c == '\'' {
			in_str = true
			quote = c
			kinds[i] = .String
			i += 1
			continue
		}
		i += 1
	}
}

@(private)
hl_apply_numbers :: proc(line: string, kinds: []Hl_Kind) {
	i := 0
	for i < len(line) {
		if kinds[i] != .Normal {
			i += 1
			continue
		}
		c := line[i]
		if c >= '0' && c <= '9' {
			start := i
			i += 1
			for i < len(line) && ((line[i] >= '0' && line[i] <= '9') || line[i] == '.') {
				if kinds[i] != .Normal {
					break
				}
				i += 1
			}
			for j in start ..< i {
				if kinds[j] == .Normal {
					kinds[j] = .Number
				}
			}
			continue
		}
		i += 1
	}
}

@(private)
hl_apply_keywords :: proc(lang: string, line: string, kinds: []Hl_Kind) {
	keywords, types := hl_words_for_lang(lang)
	i := 0
	for i < len(line) {
		if kinds[i] != .Normal {
			i += 1
			continue
		}
		if !hl_ident_start(line[i]) {
			i += 1
			continue
		}
		start := i
		i += 1
		for i < len(line) && hl_ident_char(line[i]) {
			i += 1
		}
		word := strings.to_lower(line[start:i], context.temp_allocator)
		kind: Hl_Kind
		if slice_contains(types[:], word) {
			kind = .Type
		} else if slice_contains(keywords[:], word) {
			kind = .Keyword
		} else {
			continue
		}
		for j in start ..< i {
			if kinds[j] == .Normal {
				kinds[j] = kind
			}
		}
	}
}

@(private)
hl_ident_start :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

@(private)
hl_ident_char :: proc(c: u8) -> bool {
	return hl_ident_start(c) || (c >= '0' && c <= '9')
}

@(private)
slice_contains :: proc(list: []string, word: string) -> bool {
	for w in list {
		if w == word {
			return true
		}
	}
	return false
}

@(private)
hl_words_for_lang :: proc(lang: string) -> (keywords: []string, types: []string) {
	switch lang {
	case "odin":
		return HL_ODIN_KW[:], HL_ODIN_TYPES[:]
	case "go":
		return HL_GO_KW[:], HL_GO_TYPES[:]
	case "python", "py":
		return HL_PY_KW[:], HL_PY_TYPES[:]
	case "javascript", "js":
		return HL_JS_KW[:], HL_JS_TYPES[:]
	case "typescript", "ts":
		return HL_TS_KW[:], HL_TS_TYPES[:]
	case "c":
		return HL_C_KW[:], HL_C_TYPES[:]
	case "cpp":
		return HL_CPP_KW[:], HL_CPP_TYPES[:]
	case "rust":
		return HL_RUST_KW[:], HL_RUST_TYPES[:]
	case "sh", "bash":
		return HL_SH_KW[:], HL_SH_TYPES[:]
	case "json":
		return HL_JSON_KW[:], HL_JSON_TYPES[:]
	case "markdown", "md":
		return HL_MD_KW[:], HL_MD_TYPES[:]
	}
	return HL_GO_KW[:], HL_GO_TYPES[:]
}

@(private)
HL_ODIN_KW := [?]string {
	"proc", "struct", "enum", "import", "package", "if", "else", "for", "switch",
	"case", "return", "defer", "when", "in", "not_in", "using", "where", "break",
	"continue", "cast", "transmute",
}

@(private)
HL_ODIN_TYPES := [?]string {
	"int", "uint", "f32", "f64", "bool", "string", "rune", "byte", "b8", "b16", "b32", "b64",
}

@(private)
HL_GO_KW := [?]string {
	"func", "struct", "interface", "package", "import", "if", "else", "for", "switch",
	"case", "return", "go", "defer", "var", "const", "type", "range", "map", "chan", "break",
	"continue", "select", "fallthrough", "default",
}

@(private)
HL_GO_TYPES := [?]string {
	"int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64",
	"float32", "float64", "bool", "string", "byte", "rune", "error", "any",
}

@(private)
HL_PY_KW := [?]string {
	"def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as",
	"with", "lambda", "pass", "break", "continue", "and", "or", "not", "in", "is", "raise",
	"try", "except", "finally", "yield", "async", "await",
}

@(private)
HL_PY_TYPES := [?]string {
	"true", "false", "none", "int", "float", "str", "bool", "list", "dict", "tuple", "set",
}

@(private)
HL_JS_KW := [?]string {
	"function", "const", "let", "var", "if", "else", "for", "while", "return", "import",
	"export", "class", "new", "this", "typeof", "async", "await", "break", "continue",
	"switch", "case", "default", "try", "catch", "finally", "throw", "delete", "void",
}

@(private)
HL_JS_TYPES := [?]string {
	"null", "undefined", "true", "false", "number", "string", "boolean", "object", "symbol",
}

@(private)
HL_TS_KW := [?]string {
	"function", "const", "let", "var", "if", "else", "for", "while", "return", "import",
	"export", "class", "new", "this", "typeof", "async", "await", "break", "continue",
	"switch", "case", "default", "try", "catch", "finally", "throw", "interface", "type",
	"enum", "implements", "extends", "public", "private", "protected", "readonly",
}

@(private)
HL_TS_TYPES := [?]string {
	"null", "undefined", "true", "false", "number", "string", "boolean", "object", "symbol",
	"any", "unknown", "never", "void",
}

@(private)
HL_C_KW := [?]string {
	"if", "else", "for", "while", "return", "struct", "typedef", "enum", "switch", "case",
	"break", "continue", "goto", "static", "extern", "const", "volatile", "sizeof", "do",
}

@(private)
HL_C_TYPES := [?]string {
	"void", "int", "char", "float", "double", "long", "short", "unsigned", "signed",
	"bool", "_Bool", "size_t",
}

@(private)
HL_CPP_KW := [?]string {
	"if", "else", "for", "while", "return", "struct", "class", "typedef", "enum", "switch",
	"case", "break", "continue", "goto", "static", "extern", "const", "volatile", "namespace",
	"template", "typename", "public", "private", "protected", "virtual", "override", "new",
	"delete", "using",
}

@(private)
HL_CPP_TYPES := [?]string {
	"void", "int", "char", "float", "double", "long", "short", "unsigned", "signed", "bool",
	"size_t", "auto",
}

@(private)
HL_RUST_KW := [?]string {
	"fn", "let", "mut", "if", "else", "for", "while", "return", "match", "struct", "enum",
	"impl", "trait", "use", "mod", "pub", "crate", "self", "super", "where", "async", "await",
	"loop", "break", "continue", "move", "ref", "type", "const", "static", "unsafe", "extern",
}

@(private)
HL_RUST_TYPES := [?]string {
	"i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128", "f32", "f64",
	"bool", "str", "String", "isize", "usize",
}

@(private)
HL_SH_KW := [?]string {
	"if", "then", "else", "fi", "for", "do", "done", "case", "esac", "function", "return",
	"export", "local", "while", "until", "select", "in",
}

@(private)
HL_SH_TYPES := [?]string {}

@(private)
HL_JSON_KW := [?]string {"true", "false", "null"}

@(private)
HL_JSON_TYPES := [?]string {}

@(private)
HL_MD_KW := [?]string {}

@(private)
HL_MD_TYPES := [?]string {}
