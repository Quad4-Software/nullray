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
test_parse_response_id_mismatch :: proc(t: ^testing.T) {
	line := `{"jsonrpc":"2.0","id":1,"result":{}}`
	result, err, matched := parse_response_line(line, 99)
	defer delete(result)
	defer delete(err)
	testing.expect(t, !matched)
}
