// SPDX-License-Identifier: 0BSD
/*
Streaming POST with SSE line delivery via libcurl write callback.
*/

package http

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"

Stream_Chunk_Proc :: #type proc(chunk: string, user: rawptr)

Stream_State :: struct {
	line_buf: [dynamic]u8,
	raw:      [dynamic]u8,
	on_chunk: Stream_Chunk_Proc,
	user:     rawptr,
	mu:       sync.Mutex,
	err:      string,
	done:     bool,
}

@(private)
stream_write_cb :: proc "c" (ptr: [^]u8, size: c.size_t, nmemb: c.size_t, userdata: rawptr) -> c.size_t {
	context = runtime.default_context()
	if cancel_requested() {
		return 0
	}
	total := int(size * nmemb)
	if total <= 0 || userdata == nil {
		return 0
	}
	st := cast(^Stream_State)userdata
	sync.mutex_lock(&st.mu)
	defer sync.mutex_unlock(&st.mu)
	if len(st.raw) < constants.MAX_STREAM_ERROR_BYTES {
		room := constants.MAX_STREAM_ERROR_BYTES - len(st.raw)
		n := min(total, room)
		append(&st.raw, ..ptr[:n])
	}
	append(&st.line_buf, ..ptr[:total])
	for {
		nl := -1
		for i in 0 ..< len(st.line_buf) {
			if st.line_buf[i] == '\n' {
				nl = i
				break
			}
		}
		if nl < 0 {
			break
		}
		line := string(st.line_buf[:nl])
		if strings.has_suffix(line, "\r") {
			line = line[:len(line) - 1]
		}
		if st.on_chunk != nil {
			st.on_chunk(line, st.user)
		}
		copy(st.line_buf[:], st.line_buf[nl + 1:])
		resize(&st.line_buf, len(st.line_buf) - nl - 1)
	}
	return c.size_t(total)
}

post_json_stream :: proc(
	url: string,
	headers: []string,
	body: string,
	on_chunk: Stream_Chunk_Proc,
	user: rawptr,
	timeout_sec: int = 120,
) -> Response {
	curl := curl_easy_init()
	if curl == nil {
		return Response{ok = false, err = "curl init failed"}
	}
	defer curl_easy_cleanup(curl)

	st: Stream_State
	st.line_buf = make([dynamic]u8, context.allocator)
	st.raw = make([dynamic]u8, context.allocator)
	defer delete(st.line_buf)
	defer delete(st.raw)
	st.on_chunk = on_chunk
	st.user = user

	hdr: Header_State

	// libcurl keeps pointers to URL and POSTFIELDS for the whole perform.
	// Keep them off temp_allocator so SSE callbacks cannot free them early.
	url_c := strings.clone_to_cstring(url, context.allocator)
	defer delete(url_c)
	body_c := strings.clone_to_cstring(body, context.allocator)
	defer delete(body_c)

	_ = curl_easy_setopt(curl, .URL, url_c)
	_ = curl_easy_setopt(curl, .WRITEFUNCTION, stream_write_cb)
	_ = curl_easy_setopt(curl, .WRITEDATA, &st)
	_ = curl_easy_setopt(curl, .HEADERFUNCTION, header_cb)
	_ = curl_easy_setopt(curl, .HEADERDATA, &hdr)
	_ = curl_easy_setopt(curl, .TIMEOUT, c.long(timeout_sec))
	_ = curl_easy_setopt(curl, .FOLLOWLOCATION, c.long(1))
	_ = curl_easy_setopt(curl, .USERAGENT, strings.clone_to_cstring(fmt.tprintf("nullray/%s", constants.VERSION), context.temp_allocator))
	_ = curl_easy_setopt(curl, .NOPROGRESS, c.long(0))
	_ = curl_easy_setopt(curl, .XFERINFOFUNCTION, xfer_cb)

	list: ^curl_slist
	defer if list != nil {
		curl_slist_free_all(list)
	}
	for h in headers {
		list = curl_slist_append(list, strings.clone_to_cstring(h, context.temp_allocator))
	}
	list = curl_slist_append(list, cstring("Accept: text/event-stream"))
	if list != nil {
		_ = curl_easy_setopt(curl, .HTTPHEADER, list)
	}

	_ = curl_easy_setopt(curl, .CUSTOMREQUEST, cstring("POST"))
	_ = curl_easy_setopt(curl, .POSTFIELDS, body_c)
	_ = curl_easy_setopt(curl, .POSTFIELDSIZE, c.long(len(body)))

	code := curl_easy_perform(curl)
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}
	if len(st.line_buf) > 0 && on_chunk != nil {
		on_chunk(string(st.line_buf[:]), user)
	}
	if code != .OK {
		return Response{ok = false, err = string(curl_easy_strerror(code))}
	}
	status: c.long = 0
	_ = curl_easy_getinfo(curl, .RESPONSE_CODE, &status)
	if status >= 400 {
		body := strings.clone(string(st.raw[:]), context.allocator)
		return Response{
			ok = false,
			status = int(status),
			body = body,
			err = fmt.tprintf("HTTP %d", int(status)),
			retry_after = hdr.retry_after,
		}
	}
	return Response{ok = true, status = int(status), retry_after = hdr.retry_after}
}
