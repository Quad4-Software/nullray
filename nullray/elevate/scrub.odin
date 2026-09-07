// SPDX-License-Identifier: 0BSD
/*
Scrub password bytes from captured command output before agent sees it.
*/

package elevate

import "core:mem"
import "core:strings"

REDACTED :: "[redacted]"

scrub_secret :: proc(text, secret: string, allocator := context.allocator) -> string {
	if len(secret) == 0 || len(text) == 0 {
		return strings.clone(text, allocator)
	}
	if !strings.contains(text, secret) {
		return strings.clone(text, allocator)
	}
	out, _ := strings.replace_all(text, secret, REDACTED, allocator)
	return out
}

scrub_result_inplace :: proc(r: ^Result, secret: string) {
	if r == nil || len(secret) == 0 {
		return
	}
	if len(r.stdout) > 0 {
		scrubbed := scrub_secret(r.stdout, secret)
		delete(r.stdout)
		r.stdout = scrubbed
	}
	if len(r.stderr) > 0 {
		scrubbed := scrub_secret(r.stderr, secret)
		delete(r.stderr)
		r.stderr = scrubbed
	}
	if len(r.err) > 0 {
		scrubbed := scrub_secret(r.err, secret)
		delete(r.err)
		r.err = scrubbed
	}
}

zero_bytes :: proc(s: string) {
	if len(s) == 0 {
		return
	}
	// Mutable view of owned string bytes.
	p := transmute([^]u8)raw_data(s)
	mem.zero(p, len(s))
}

zero_and_delete :: proc(s: string) {
	zero_bytes(s)
	delete(s)
}

auth_failure_text :: proc(stderr: string) -> bool {
	lower := strings.to_lower(stderr, context.temp_allocator)
	needles := []string{
		"sorry",
		"authentication failure",
		"authentication failed",
		"incorrect password",
		"try again",
		"a password is required",
		"no password was provided",
		"not allowed to run",
	}
	for n in needles {
		if strings.contains(lower, n) {
			return true
		}
	}
	return false
}

requiretty_text :: proc(stderr: string) -> bool {
	lower := strings.to_lower(stderr, context.temp_allocator)
	return strings.contains(lower, "requiretty") ||
		strings.contains(lower, "a terminal is required") ||
		strings.contains(lower, "no tty present")
}
