/*
MCP client handshake, tool listing, and tool invocation.
*/

package mcp

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:tools"

MCP_PROTOCOL_VERSION :: "2024-11-05"

client_initialize :: proc(session: ^Stdio_Session, allocator := context.allocator) -> (err: string) {
	if session == nil {
		return strings.clone("nil session", allocator)
	}

	params := fmt.aprintf(
		`{"protocolVersion":%q,"capabilities":{},"clientInfo":{"name":"nullray","version":%q}}`,
		MCP_PROTOCOL_VERSION,
		constants.VERSION,
		allocator = allocator,
	)
	defer delete(params)

	_, init_err := stdio_request(session, "initialize", params, allocator)
	if init_err != "" {
		return init_err
	}

	notify := build_notification("notifications/initialized", "", allocator)
	defer delete(notify)
	if werr := stdio_write_line(session, notify); werr != "" {
		return strings.clone(werr, allocator)
	}
	return ""
}

client_list_tools :: proc(
	session: ^Stdio_Session,
	server_id: string,
	allocator := context.allocator,
) -> (
	tools_out: []tools.Tool,
	err: string,
) {
	result_json, req_err := stdio_request(session, "tools/list", `{}`, allocator)
	if req_err != "" {
		return nil, req_err
	}
	defer delete(result_json)

	doc, parse_err := json.parse_string(result_json, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return nil, fmt.aprintf("tools/list parse failed: %v", parse_err, allocator = allocator)
	}
	root, ok := doc.(json.Object)
	if !ok {
		return nil, strings.clone("tools/list result must be object", allocator)
	}
	tools_v, found := root["tools"]
	if !found {
		return nil, strings.clone("tools/list missing tools array", allocator)
	}
	arr, arr_ok := tools_v.(json.Array)
	if !arr_ok {
		return nil, strings.clone("tools/list tools must be array", allocator)
	}

	out := make([dynamic]tools.Tool, allocator)
	for item in arr {
		tobj, tok := item.(json.Object)
		if !tok {
			continue
		}
		tool_name := ""
		if nv, nok := tobj["name"]; nok {
			if s, sok := nv.(json.String); sok {
				tool_name = string(s)
			}
		}
		if len(tool_name) == 0 {
			continue
		}

		desc := ""
		if dv, dok := tobj["description"]; dok {
			if s, sok := dv.(json.String); sok {
				desc = string(s)
			}
		}

		schema := strings.clone(`{"type":"object","properties":{}}`, allocator)
		if sv, sok := tobj["inputSchema"]; sok {
			if unparsed, uerr := json.unparse(sv, allocator = allocator); uerr == nil {
				delete(schema)
				schema = unparsed
			}
		}

		full_name := fmt.aprintf("mcp:%s:%s", server_id, tool_name, allocator = allocator)
		g_tool_routes[full_name] = Mcp_Tool_Route{
			server_id = strings.clone(server_id, allocator),
			tool_name = strings.clone(tool_name, allocator),
		}

		append(&out, tools.Tool{
			name = full_name,
			description = strings.clone(desc, allocator),
			schema_json = schema,
			run = nil,
		})
	}
	return out[:], ""
}

client_call_tool :: proc(
	session: ^Stdio_Session,
	tool_name: string,
	args_json: string,
	allocator := context.allocator,
) -> (
	result: string,
	err: string,
) {
	params_b: strings.Builder
	strings.builder_init(&params_b, context.temp_allocator)
	strings.write_string(&params_b, `{"name":`)
	write_json_string(&params_b, tool_name)
	strings.write_string(&params_b, `,"arguments":`)
	if len(args_json) > 0 {
		strings.write_string(&params_b, args_json)
	} else {
		strings.write_string(&params_b, `{}`)
	}
	strings.write_byte(&params_b, '}')
	params := strings.to_string(params_b)

	result_json, req_err := stdio_request(session, "tools/call", params, allocator)
	if req_err != "" {
		return "", req_err
	}
	defer delete(result_json)

	return format_tool_call_result(result_json, allocator)
}

@(private)
format_tool_call_result :: proc(result_json: string, allocator := context.allocator) -> (result: string, err: string) {
	doc, parse_err := json.parse_string(result_json, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return strings.clone(result_json, allocator), ""
	}
	root, ok := doc.(json.Object)
	if !ok {
		return strings.clone(result_json, allocator), ""
	}
	content_v, found := root["content"]
	if !found {
		return strings.clone(result_json, allocator), ""
	}
	arr, arr_ok := content_v.(json.Array)
	if !arr_ok {
		return strings.clone(result_json, allocator), ""
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	for item, i in arr {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		obj, obj_ok := item.(json.Object)
		if !obj_ok {
			continue
		}
		if tv, tok := obj["text"]; tok {
			if s, sok := tv.(json.String); sok {
				strings.write_string(&b, string(s))
			}
		}
	}
	if strings.builder_len(b) == 0 {
		return strings.clone(result_json, allocator), ""
	}
	return strings.to_string(b), ""
}
