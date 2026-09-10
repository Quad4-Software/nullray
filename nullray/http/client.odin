// SPDX-License-Identifier: 0BSD
/*
HTTP client API: GET/POST, redirects, and response helpers.
*/

package http

import "core:fmt"
import "core:strings"
import "nullray:constants"

Response :: struct {
	status:      int,
	body:        string,
	ok:          bool,
	err:         string,
	retry_after: int,
}

Url_Allow :: #type proc(url: string) -> bool

Request :: struct {
	method:    string,
	url:       string,
	headers:   []string,
	body:      string,
	timeout:   int,
	max_body:  int,
	allow_url: Url_Allow,
}

global_init :: proc() -> bool {
	return nullray_tls_global_init() == 0
}

global_cleanup :: proc() {
	nullray_tls_global_cleanup()
}

get :: proc(url: string, headers: []string = {}, timeout_sec: int = 30, allocator := context.allocator) -> Response {
	return do_request(Request{
		method = "GET",
		url = url,
		headers = headers,
		timeout = timeout_sec,
	}, allocator)
}

get_max :: proc(
	url: string,
	headers: []string = {},
	timeout_sec: int = 30,
	max_body: int = 0,
	allocator := context.allocator,
) -> Response {
	return do_request(Request{
		method = "GET",
		url = url,
		headers = headers,
		timeout = timeout_sec,
		max_body = max_body,
	}, allocator)
}

get_checked :: proc(
	url: string,
	headers: []string = {},
	timeout_sec: int = 30,
	allow_url: Url_Allow = nil,
	allocator := context.allocator,
) -> Response {
	return do_request(Request{
		method = "GET",
		url = url,
		headers = headers,
		timeout = timeout_sec,
		allow_url = allow_url,
	}, allocator)
}

post_json :: proc(url: string, headers: []string, body: string, timeout_sec: int = 120, allocator := context.allocator) -> Response {
	return do_request(Request{
		method = "POST",
		url = url,
		headers = headers,
		body = body,
		timeout = timeout_sec,
	}, allocator)
}

do_request :: proc(req: Request, allocator := context.allocator) -> Response {
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}

	max_body := req.max_body
	if max_body <= 0 {
		max_body = constants.DEFAULT_FETCH_MAX_BYTES
	}
	status, resp_body, retry_after, rerr := run_request(
		req.method,
		req.url,
		req.headers,
		req.body,
		req.timeout,
		max_body,
		req.allow_url,
	)
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}
	if rerr != "" {
		return Response{ok = false, err = strings.clone(rerr, allocator)}
	}

	out := strings.clone(string(resp_body), allocator)
	if status >= 400 {
		return Response{
			ok = false,
			body = out,
			status = status,
			err = fmt.aprintf("HTTP %d", status, allocator = allocator),
			retry_after = retry_after,
		}
	}
	return Response{ok = true, body = out, status = status, retry_after = retry_after}
}

join_url :: proc(base, path: string, allocator := context.temp_allocator) -> string {
	b := strings.trim_right(base, "/")
	p := path
	if !strings.has_prefix(p, "/") {
		return fmt.aprintf("%s/%s", b, path, allocator = allocator)
	}
	return fmt.aprintf("%s%s", b, p, allocator = allocator)
}
