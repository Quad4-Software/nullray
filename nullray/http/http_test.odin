// SPDX-License-Identifier: 0BSD
package http

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"

Server_Args :: struct {
	listener: net.TCP_Socket,
	response: string,
}

server_once :: proc(th: ^thread.Thread) {
	args := cast(^Server_Args)th.data
	client, _, err := net.accept_tcp(args.listener)
	if err != nil {
		return
	}
	defer net.close(client)
	buf: [8192]u8
	net.recv_tcp(client, buf[:])
	net.send_tcp(client, transmute([]u8)args.response)
}

@(private)
start_local_server :: proc(response: string, allocator := context.allocator) -> (port: int, args: ^Server_Args, th: ^thread.Thread) {
	listener, err := net.listen_tcp({net.IP4_Loopback, 0})
	if err != nil {
		return 0, nil, nil
	}
	bound, _ := net.bound_endpoint(listener)
	args = new(Server_Args, allocator)
	args.listener = listener
	args.response = response
	th = thread.create(server_once)
	th.data = args
	thread.start(th)
	return bound.port, args, th
}

@(private)
stop_local_server :: proc(args: ^Server_Args, th: ^thread.Thread, allocator := context.allocator) {
	if args != nil {
		net.close(args.listener)
		free(args, allocator)
	}
	if th != nil {
		thread.join(th)
		thread.destroy(th)
	}
}

Redirect_Args :: struct {
	listener: net.TCP_Socket,
	first:    string,
	second:   string,
}

@(test)
test_http_get_local :: proc(t: ^testing.T) {
	resp := "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
	port, args, th := start_local_server(resp)
	defer stop_local_server(args, th)
	testing.expect(t, port > 0)

	url := fmt.tprintf("http://127.0.0.1:%d/", port, context.temp_allocator)
	res := get(url, {}, 5, context.temp_allocator)
	testing.expect(t, res.ok, res.err)
	testing.expect_value(t, res.status, 200)
	testing.expect_value(t, res.body, "hello")
}

@(test)
test_http_chunked_local :: proc(t: ^testing.T) {
	// Two chunks: "hello" + "!" then terminating 0 chunk. Includes prefetch-style framing.
	resp := "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nhello\r\n1\r\n!\r\n0\r\n\r\n"
	port, args, th := start_local_server(resp)
	defer stop_local_server(args, th)
	testing.expect(t, port > 0)

	url := fmt.tprintf("http://127.0.0.1:%d/c", port, context.temp_allocator)
	res := get(url, {}, 5, context.temp_allocator)
	testing.expect(t, res.ok, res.err)
	testing.expect_value(t, res.status, 200)
	testing.expect_value(t, res.body, "hello!")
}

@(test)
test_http_post_json_local :: proc(t: ^testing.T) {
	resp := "HTTP/1.1 201 Created\r\nContent-Length: 7\r\nConnection: close\r\n\r\n{\"ok\":1}"
	port, args, th := start_local_server(resp)
	defer stop_local_server(args, th)
	testing.expect(t, port > 0)

	url := fmt.tprintf("http://127.0.0.1:%d/v1", port, context.temp_allocator)
	res := post_json(url, {"X-Test: 1"}, `{"a":1}`, 5, context.temp_allocator)
	testing.expect(t, res.ok, res.err)
	testing.expect_value(t, res.status, 201)
	testing.expect(t, strings.contains(res.body, "ok"))
}

@(test)
test_http_redirect_local :: proc(t: ^testing.T) {
	redir := new(Redirect_Args, context.allocator)
	defer free(redir)
	redir^ = Redirect_Args{
		first = "HTTP/1.1 302 Found\r\nLocation: /final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
		second = "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nyes",
	}

	listener, err := net.listen_tcp({net.IP4_Loopback, 0})
	testing.expectf(t, err == nil, "listen failed")
	defer net.close(listener)
	bound, _ := net.bound_endpoint(listener)
	port := bound.port
	redir.listener = listener

	th := thread.create(proc(th: ^thread.Thread) {
		a := cast(^Redirect_Args)th.data
		for i in 0 ..< 2 {
			client, _, aerr := net.accept_tcp(a.listener)
			if aerr != nil {
				return
			}
			buf: [8192]u8
			net.recv_tcp(client, buf[:])
			if i == 0 {
				net.send_tcp(client, transmute([]u8)a.first)
			} else {
				net.send_tcp(client, transmute([]u8)a.second)
			}
			net.close(client)
		}
	})
	defer thread.destroy(th)
	th.data = redir
	thread.start(th)

	url := fmt.tprintf("http://127.0.0.1:%d/start", port, context.temp_allocator)
	res := get(url, {}, 5, context.temp_allocator)
	thread.join(th)
	testing.expect(t, res.ok, res.err)
	testing.expect_value(t, res.body, "yes")
}

@(test)
test_join_url :: proc(t: ^testing.T) {
	testing.expect_value(t, join_url("https://api.example.com", "/v1/x"), "https://api.example.com/v1/x")
	testing.expect_value(t, join_url("https://api.example.com/", "v1/x"), "https://api.example.com/v1/x")
}

@(test)
test_host_header_no_double_port :: proc(t: ^testing.T) {
	parts, err := parse_url("http://127.0.0.1:11434/v1/chat/completions")
	testing.expect_value(t, err, "")
	testing.expect_value(t, host_header_value(parts), "127.0.0.1:11434")
	parts2, err2 := parse_url("https://api.example.com/v1")
	testing.expect_value(t, err2, "")
	testing.expect_value(t, host_header_value(parts2), "api.example.com")
}

@(test)
test_http_proxy_connect_local :: proc(t: ^testing.T) {
	resp := "HTTP/1.1 200 Connection Established\r\n\r\n"
	port, args, th := start_local_server(resp)
	defer stop_local_server(args, th)
	testing.expect(t, port > 0)

	os.set_env("HTTP_PROXY", fmt.tprintf("http://127.0.0.1:%d", port))
	defer os.unset_env("HTTP_PROXY")
	os.unset_env("NO_PROXY")

	parts := Url_Parts{
		scheme = "http",
		host = "example.com",
		hostname = "example.com",
		port = 80,
		path = "/",
		use_tls = false,
	}
	px := proxy_for_url(parts)
	testing.expect(t, px.ok)
	conn, err := conn_dial_proxy_connect(parts, px, 5)
	testing.expect_value(t, err, "")
	testing.expect(t, conn.sock != 0)
	conn_close(&conn)
}
