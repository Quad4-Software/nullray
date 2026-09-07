package mcp

import "core:strings"
import "core:testing"

@(test)
test_build_request_and_notification :: proc(t: ^testing.T) {
	req := build_request(1, "tools/list", `{}`)
	defer delete(req)
	testing.expect(t, strings.contains(req, `"jsonrpc":"2.0"`))
	testing.expect(t, strings.contains(req, `"id":1`))
	testing.expect(t, strings.contains(req, `"method":"tools/list"`))

	note := build_notification("notifications/initialized", "")
	defer delete(note)
	testing.expect(t, strings.contains(note, `"method":"notifications/initialized"`))
	testing.expect(t, !strings.contains(note, `"id"`))
}

@(test)
test_parse_response_ok :: proc(t: ^testing.T) {
	line := `{"jsonrpc":"2.0","id":7,"result":{"tools":[]}}`
	result, err, matched := parse_response_line(line, 7)
	defer delete(result)
	defer delete(err)
	testing.expect(t, matched)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(result, `"tools"`))
}

@(test)
test_parse_response_error :: proc(t: ^testing.T) {
	line := `{"jsonrpc":"2.0","id":3,"error":{"code":-32600,"message":"bad"}}`
	result, err, matched := parse_response_line(line, 3)
	defer delete(result)
	defer delete(err)
	testing.expect(t, matched)
	testing.expect_value(t, result, "")
	testing.expect_value(t, err, "bad")
}

@(test)
test_mcp_protocol_versions_span :: proc(t: ^testing.T) {
	testing.expect_value(t, MCP_PROTOCOL_OLDEST, "2024-10-07")
	testing.expect_value(t, MCP_PROTOCOL_LATEST, "2025-11-25")
	testing.expect(t, mcp_version_supported(MCP_PROTOCOL_OLDEST))
	testing.expect(t, mcp_version_supported(MCP_PROTOCOL_LATEST))
	testing.expect(t, mcp_version_supported("2024-11-05"))
	testing.expect(t, !mcp_version_supported("2026-07-28"))
	testing.expect(t, !mcp_version_supported(""))
}

@(test)
test_parse_initialize_protocol_version :: proc(t: ^testing.T) {
	v := parse_initialize_protocol_version(`{"protocolVersion":"2024-11-05","capabilities":{}}`)
	defer delete(v)
	testing.expect_value(t, v, "2024-11-05")
}
