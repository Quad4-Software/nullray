// SPDX-License-Identifier: 0BSD
package http

import "core:os"
import "core:testing"

@(test)
test_parse_proxy_and_no_proxy :: proc(t: ^testing.T) {
	px := parse_proxy_url("http://user:pass@127.0.0.1:8080")
	testing.expect(t, px.ok)
	testing.expect_value(t, px.hostname, "127.0.0.1")
	testing.expect_value(t, px.port, 8080)
	testing.expect_value(t, px.userinfo, "user:pass")

	px2 := parse_proxy_url("proxy.example.com:3128")
	testing.expect(t, px2.ok)
	testing.expect_value(t, px2.port, 3128)

	os.set_env("NO_PROXY", "localhost,example.com")
	defer os.unset_env("NO_PROXY")
	testing.expect(t, proxy_host_excluded("localhost"))
	testing.expect(t, proxy_host_excluded("foo.example.com"))
	testing.expect(t, !proxy_host_excluded("openrouter.ai"))
}
