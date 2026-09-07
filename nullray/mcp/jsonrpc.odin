// SPDX-License-Identifier: 0BSD
/*
JSON-RPC 2.0 line helpers for MCP stdio transport.
*/

package mcp

import "core:encoding/json"
import "core:fmt"
import "core:strings"

build_request :: proc(id: int, method: string, params_json: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	fmt.sbprint(&b, id)
	strings.write_string(&b, `,"method":`)
	write_json_string(&b, method)
	if len(params_json) > 0 {
		strings.write_string(&b, `,"params":`)
		strings.write_string(&b, params_json)
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

build_notification :: proc(method: string, params_json: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","method":`)
	write_json_string(&b, method)
	if len(params_json) > 0 {
		strings.write_string(&b, `,"params":`)
		strings.write_string(&b, params_json)
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

parse_response_line :: proc(
	line: string,
	expect_id: int,
	allocator := context.allocator,
) -> (
	result_json: string,
	err: string,
	matched: bool,
) {
	doc, parse_err := json.parse_string(line, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return "", fmt.aprintf("bad JSON-RPC line: %v", parse_err, allocator = allocator), true
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return "", strings.clone("JSON-RPC root must be object", allocator), true
	}
	if method_v, has_method := obj["method"]; has_method {
		if _, is_str := method_v.(json.String); is_str {
			return "", "", false
		}
	}
	id_v, has_id := obj["id"]
	if !has_id {
		return "", "", false
	}
	id_ok := false
	switch id in id_v {
	case json.Integer:
		id_ok = int(id) == expect_id
	case json.Float:
		id_ok = int(id) == expect_id
	case json.Null, bool, json.String, json.Array, json.Object:
		return "", "", false
	}
	if !id_ok {
		return "", "", false
	}
	if err_v, has_err := obj["error"]; has_err {
		if err_obj, ok := err_v.(json.Object); ok {
			if msg_v, mok := err_obj["message"]; mok {
				if s, sok := msg_v.(json.String); sok {
					return "", strings.clone(string(s), allocator), true
				}
			}
		}
		return "", strings.clone("JSON-RPC error", allocator), true
	}
	if res_v, has_res := obj["result"]; has_res {
		opt: json.Marshal_Options
		res_b: strings.Builder
		strings.builder_init(&res_b, context.temp_allocator)
		if uerr := json.unparse_to_builder(&res_b, res_v, &opt); uerr != nil {
			return "", fmt.aprintf("unparse result failed: %v", uerr, allocator = allocator), true
		}
		return strings.clone(strings.to_string(res_b), allocator), "", true
	}
	return "", strings.clone("JSON-RPC response missing result", allocator), true
}

write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(b, `\u%04x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
	strings.write_byte(b, '"')
}
