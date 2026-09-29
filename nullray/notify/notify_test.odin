// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package notify

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_notify_sanitize_strips_controls :: proc(t: ^testing.T) {
	out := notify_sanitize("a\x1b]9;evil\x07b\nline2", 200, context.temp_allocator)
	testing.expect(t, strings.index(out, "\x1b") < 0)
	testing.expect(t, strings.index(out, "\x07") < 0)
	testing.expect(t, strings.index(out, "evil") >= 0)
	testing.expect(t, len(out) <= 200)
}

@(test)
test_notify_sanitize_truncates :: proc(t: ^testing.T) {
	long := strings.repeat("x", 500, context.temp_allocator)
	out := notify_sanitize(long, 80, context.temp_allocator)
	testing.expect(t, len(out) == 80)
}

@(test)
test_notify_backend_env :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_NOTIFY, "osc")
	defer os.unset_env(constants.ENV_NOTIFY)
	testing.expect(t, notify_backend() == .Osc)
	os.set_env(constants.ENV_NOTIFY, "off")
	testing.expect(t, notify_backend() == .Off)
	os.set_env(constants.ENV_NOTIFY, "garbage")
	testing.expect(t, notify_backend() == .Auto)
}

@(test)
test_notify_ps_quote_escapes :: proc(t: ^testing.T) {
	q := notify_ps_quote("it's ok", context.temp_allocator)
	testing.expect_value(t, q, `'it''s ok'`)
}

@(test)
test_notify_applescript_quote_escapes :: proc(t: ^testing.T) {
	q := notify_applescript_quote(`say "hi" \ done`, context.temp_allocator)
	testing.expect_value(t, q, `"say \"hi\" \\ done"`)
}

@(test)
test_notify_send_off_is_noop :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_NOTIFY, "off")
	defer os.unset_env(constants.ENV_NOTIFY)
	// Must not spawn, write escapes, or crash.
	notify_send("title", "body")
}
