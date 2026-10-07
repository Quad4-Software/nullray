// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
GBNF grammar generation for constrained tool-call decoding on llama.cpp.

llama.cpp /chat/completions accepts a top level "grammar" field holding a GBNF
grammar that constrains the raw assistant output. The grammar emitted here
mirrors the envelope llama.cpp's own generic tool-call handler uses: the model
answers either with {"response": "..."} for plain text or calls tools via
{"tool_call": {...}} / {"tool_calls": [...]}, each call shaped
{"name": <tool>, "arguments": <object matching the tool parameters schema>}.

The schema to grammar walk lives in tool_grammar_schema.odin.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
Gbnf :: struct {
	b:    strings.Builder,
	next: int,
}

@(private)
gbnf_rule :: proc(g: ^Gbnf, name, body: string) {
	strings.write_string(&g.b, name)
	strings.write_string(&g.b, " ::= ")
	strings.write_string(&g.b, body)
	strings.write_byte(&g.b, '\n')
}

// Unique rule name derived from a base plus a counter.
@(private)
gbnf_sub :: proc(g: ^Gbnf, base: string) -> string {
	n := g.next
	g.next += 1
	return fmt.tprintf("%s-%d", base, n)
}

// Write s as a GBNF "..." literal with escaping.
@(private)
gbnf_write_lit :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\t':
			strings.write_string(b, `\t`)
		case '\r':
			strings.write_string(b, `\r`)
		case:
			if r < 0x20 || r == 0x7F {
				fmt.sbprintf(b, `\x%02x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
	strings.write_byte(b, '"')
}

@(private)
gbnf_lit_string :: proc(s: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	gbnf_write_lit(&b, s)
	return strings.to_string(b)
}

// Literal for a JSON value: marshal then quote as a GBNF literal so enum and
// const members land as exact output bytes ("\"x\"", "42", "true").
@(private)
gbnf_lit_json :: proc(v: json.Value, allocator := context.temp_allocator) -> string {
	data, err := json.marshal(v, allocator = allocator)
	if err != nil {
		return `"null"`
	}
	return gbnf_lit_string(string(data), allocator)
}

/*
Build a GBNF grammar constraining output to plain text or tool calls for the
tool list in tools_json (OpenAI [{"type":"function","function":{...}}] form).
parallel=false collapses the call list to a single call. Caller uses the
returned string immediately, it may live on the temp allocator.
*/
tool_grammar_build :: proc(tools_json: string, parallel: bool, allocator := context.allocator) -> (string, bool) {
	doc, perr := json.parse_string(tools_json, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return "", false
	}
	arr, ok := doc.(json.Array)
	if !ok || len(arr) == 0 {
		return "", false
	}
	g: Gbnf
	strings.builder_init(&g.b, allocator)

	calls := make([dynamic]string, context.temp_allocator)
	for item, i in arr {
		to, iok := item.(json.Object)
		if !iok {
			continue
		}
		fnv, fhas := to["function"]
		if !fhas {
			continue
		}
		fn, fok := fnv.(json.Object)
		if !fok {
			continue
		}
		nv, nhas := fn["name"]
		if !nhas {
			continue
		}
		ns, sok := nv.(json.String)
		if !sok || len(ns) == 0 {
			continue
		}
		call := fmt.tprintf("call-%d", i)
		arg := "any-obj"
		if pv, has := fn["parameters"]; has {
			arg = gbnf_schema_rule(&g, fmt.tprintf("args-%d", i), pv)
		}
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, `"{" ws "\"name\"" ws ":" ws `)
		// Marshal gives the JSON encoded form ("name"), the literal then
		// matches the wire bytes including the quotes.
		strings.write_string(&b, gbnf_lit_json(nv))
		strings.write_string(&b, ` ws "," ws "\"arguments\"" ws ":" ws `)
		strings.write_string(&b, arg)
		strings.write_string(&b, ` ("," ws "\"id\"" ws ":" ws str)? "}" ws`)
		gbnf_rule(&g, call, strings.to_string(b))
		append(&calls, call)
	}
	if len(calls) == 0 {
		return "", false
	}

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for c, i in calls {
		if i > 0 {
			strings.write_string(&b, " | ")
		}
		strings.write_string(&b, c)
	}
	gbnf_rule(&g, "call", strings.to_string(b))
	if parallel {
		gbnf_rule(&g, "call-list", `"[" ws call ("," ws call)* "]" ws`)
	} else {
		gbnf_rule(&g, "call-list", `"[" ws call "]" ws`)
	}
	gbnf_rule(&g, "env-calls", `"{" ws "\"tool_calls\"" ws ":" ws call-list "}" ws`)
	gbnf_rule(&g, "env-call", `"{" ws "\"tool_call\"" ws ":" ws call "}" ws`)
	gbnf_rule(&g, "env-resp", `"{" ws "\"response\"" ws ":" ws str "}" ws`)
	gbnf_rule(&g, "root", `ws ( env-calls | env-call | env-resp )`)

	// Every value rule ends in ws so members may carry trailing whitespace.
	gbnf_rule(&g, "ws", `[ \t\n]*`)
	gbnf_rule(&g, "hex", `[0-9a-fA-F]`)
	gbnf_rule(&g, "str", `"\"" ( [^"\\\x00-\x1F\x7F] | "\\" ( ["\\/bfnrt] | "u" hex hex hex hex ) )* "\"" ws`)
	gbnf_rule(&g, "num", `"-"? ( "0" | [1-9] [0-9]* ) ( "." [0-9]+ )? ( [eE] [+-]? [0-9]+ )? ws`)
	gbnf_rule(&g, "int", `"-"? ( "0" | [1-9] [0-9]* ) ws`)
	gbnf_rule(&g, "bool", `( "true" | "false" ) ws`)
	gbnf_rule(&g, "val", `( any-obj | any-arr | str | num | "true" | "false" | "null" ) ws`)
	gbnf_rule(&g, "any-obj", `"{" ws ( str ":" ws val ("," ws str ":" ws val)* )? "}" ws`)
	gbnf_rule(&g, "any-arr", `"[" ws ( val ("," ws val)* )? "]" ws`)

	return strings.to_string(g.b), true
}
