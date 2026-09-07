// SPDX-License-Identifier: 0BSD
/*
Thin libcurl binding for HTTPS chat requests.
*/

package http

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:constants"

when ODIN_OS == .Windows {
	foreign import lib {"system:libcurl.lib"}
} else {
	foreign import lib {"system:curl"}
}

CURL :: struct {}

CURLcode :: enum c.int {
	OK = 0,
}

OPTTYPE_LONG :: 0
OPTTYPE_OBJECTPOINT :: 10000
OPTTYPE_FUNCTIONPOINT :: 20000

CURLoption :: enum c.int {
	WRITEDATA        = OPTTYPE_OBJECTPOINT + 1,
	URL              = OPTTYPE_OBJECTPOINT + 2,
	WRITEFUNCTION    = OPTTYPE_FUNCTIONPOINT + 11,
	TIMEOUT          = OPTTYPE_LONG + 13,
	POSTFIELDS       = OPTTYPE_OBJECTPOINT + 15,
	HTTPHEADER       = OPTTYPE_OBJECTPOINT + 23,
	HEADERDATA       = OPTTYPE_OBJECTPOINT + 29,
	USERAGENT        = OPTTYPE_OBJECTPOINT + 18,
	FOLLOWLOCATION   = OPTTYPE_LONG + 52,
	POSTFIELDSIZE    = OPTTYPE_LONG + 60,
	CUSTOMREQUEST    = OPTTYPE_OBJECTPOINT + 36,
	NOPROGRESS       = OPTTYPE_LONG + 43,
	HEADERFUNCTION   = OPTTYPE_FUNCTIONPOINT + 79,
	XFERINFOFUNCTION = OPTTYPE_FUNCTIONPOINT + 219,
	XFERINFODATA     = OPTTYPE_OBJECTPOINT + 219,
}

curl_slist :: struct {
	data: cstring,
	next: ^curl_slist,
}

CURLinfo :: enum c.int {
	RESPONSE_CODE = 0x200002,
}

@(default_calling_convention = "c")
foreign lib {
	curl_easy_init :: proc() -> ^CURL ---
	curl_easy_setopt :: proc(curl: ^CURL, option: CURLoption, #c_vararg args: ..any) -> CURLcode ---
	curl_easy_getinfo :: proc(curl: ^CURL, info: CURLinfo, #c_vararg args: ..any) -> CURLcode ---
	curl_easy_perform :: proc(curl: ^CURL) -> CURLcode ---
	curl_easy_cleanup :: proc(curl: ^CURL) ---
	curl_easy_strerror :: proc(code: CURLcode) -> cstring ---
	curl_slist_append :: proc(list: ^curl_slist, data: cstring) -> ^curl_slist ---
	curl_slist_free_all :: proc(list: ^curl_slist) ---
	curl_global_init :: proc(flags: c.long) -> CURLcode ---
	curl_global_cleanup :: proc() ---
}

CURL_GLOBAL_DEFAULT :: c.long(3)

Body_Buf :: struct {
	data: [dynamic]u8,
}

@(private)
write_cb :: proc "c" (ptr: [^]u8, size: c.size_t, nmemb: c.size_t, userdata: rawptr) -> c.size_t {
	context = runtime.default_context()
	if cancel_requested() {
		return 0
	}
	total := int(size * nmemb)
	if total <= 0 || userdata == nil {
		return 0
	}
	buf := cast(^Body_Buf)userdata
	append(&buf.data, ..ptr[:total])
	return c.size_t(total)
}

@(private)
xfer_cb :: proc "c" (
	clientp: rawptr,
	dltotal: c.long,
	dlnow: c.long,
	ultotal: c.long,
	ulnow: c.long,
) -> c.int {
	context = runtime.default_context()
	_ = clientp
	_ = dltotal
	_ = dlnow
	_ = ultotal
	_ = ulnow
	if cancel_requested() {
		return 1
	}
	return 0
}

global_init :: proc() -> bool {
	return curl_global_init(CURL_GLOBAL_DEFAULT) == .OK
}

global_cleanup :: proc() {
	curl_global_cleanup()
}

Response :: struct {
	status:      int,
	body:        string,
	ok:          bool,
	err:         string,
	retry_after: int,
}

Header_State :: struct {
	retry_after: int,
}

@(private)
header_cb :: proc "c" (ptr: [^]u8, size: c.size_t, nmemb: c.size_t, userdata: rawptr) -> c.size_t {
	context = runtime.default_context()
	total := int(size * nmemb)
	if total <= 0 || userdata == nil {
		return 0
	}
	st := cast(^Header_State)userdata
	line := string(ptr[:total])
	lower := strings.to_lower(line, context.temp_allocator)
	if strings.has_prefix(lower, "retry-after:") {
		rest := strings.trim_space(line[len("retry-after:"):])
		n, ok := strconv.parse_int(rest)
		if ok && n > 0 {
			st.retry_after = n
		}
	}
	return c.size_t(total)
}

Request :: struct {
	method:  string,
	url:     string,
	headers: []string,
	body:    string,
	timeout: int,
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

get :: proc(url: string, headers: []string = {}, timeout_sec: int = 30, allocator := context.allocator) -> Response {
	return do_request(Request{
		method = "GET",
		url = url,
		headers = headers,
		timeout = timeout_sec,
	}, allocator)
}

do_request :: proc(req: Request, allocator := context.allocator) -> Response {
	curl := curl_easy_init()
	if curl == nil {
		return Response{ok = false, err = "curl init failed"}
	}
	defer curl_easy_cleanup(curl)

	buf: Body_Buf
	buf.data = make([dynamic]u8, allocator)
	defer delete(buf.data)

	hdr: Header_State

	url_c := strings.clone_to_cstring(req.url, context.allocator)
	defer delete(url_c)
	_ = curl_easy_setopt(curl, .URL, url_c)
	_ = curl_easy_setopt(curl, .WRITEFUNCTION, write_cb)
	_ = curl_easy_setopt(curl, .WRITEDATA, &buf)
	_ = curl_easy_setopt(curl, .HEADERFUNCTION, header_cb)
	_ = curl_easy_setopt(curl, .HEADERDATA, &hdr)
	_ = curl_easy_setopt(curl, .TIMEOUT, c.long(req.timeout))
	_ = curl_easy_setopt(curl, .FOLLOWLOCATION, c.long(1))
	_ = curl_easy_setopt(curl, .USERAGENT, strings.clone_to_cstring(fmt.tprintf("nullray/%s", constants.VERSION), context.temp_allocator))
	_ = curl_easy_setopt(curl, .NOPROGRESS, c.long(0))
	_ = curl_easy_setopt(curl, .XFERINFOFUNCTION, xfer_cb)

	list: ^curl_slist
	defer if list != nil {
		curl_slist_free_all(list)
	}
	for h in req.headers {
		list = curl_slist_append(list, strings.clone_to_cstring(h, context.temp_allocator))
	}
	if list != nil {
		_ = curl_easy_setopt(curl, .HTTPHEADER, list)
	}

	body_c: cstring
	if req.method == "POST" {
		_ = curl_easy_setopt(curl, .CUSTOMREQUEST, cstring("POST"))
		body_c = strings.clone_to_cstring(req.body, context.allocator)
		_ = curl_easy_setopt(curl, .POSTFIELDS, body_c)
		_ = curl_easy_setopt(curl, .POSTFIELDSIZE, c.long(len(req.body)))
	} else if req.method != "GET" && len(req.method) > 0 {
		_ = curl_easy_setopt(curl, .CUSTOMREQUEST, strings.clone_to_cstring(req.method, context.temp_allocator))
	}
	defer if body_c != nil {
		delete(body_c)
	}

	code := curl_easy_perform(curl)
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}
	if code != .OK {
		return Response{ok = false, err = string(curl_easy_strerror(code))}
	}

	status: c.long = 0
	_ = curl_easy_getinfo(curl, .RESPONSE_CODE, &status)
	body := string(buf.data[:])
	out := strings.clone(body, allocator)
	if status >= 400 {
		return Response{
			ok = false,
			body = out,
			status = int(status),
			err = fmt.aprintf("HTTP %d", int(status), allocator = allocator),
			retry_after = hdr.retry_after,
		}
	}
	return Response{ok = true, body = out, status = int(status), retry_after = hdr.retry_after}
}

join_url :: proc(base, path: string, allocator := context.temp_allocator) -> string {
	b := strings.trim_right(base, "/")
	p := path
	if !strings.has_prefix(p, "/") {
		return fmt.aprintf("%s/%s", b, path, allocator = allocator)
	}
	return fmt.aprintf("%s%s", b, p, allocator = allocator)
}
