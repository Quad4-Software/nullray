// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package http

import "core:testing"

@(test)
test_cancel_is_owner_scoped :: proc(t: ^testing.T) {
	a, b: int
	cancel_request(&a)
	defer cancel_clear(&a)
	testing.expect(t, cancel_requested(&a))
	testing.expect(t, !cancel_requested(&b))
	testing.expect(t, !cancel_requested(nil))
	cancel_clear(&a)
	testing.expect(t, !cancel_requested(&a))
}

@(test)
test_cancel_thread_binding :: proc(t: ^testing.T) {
	owner: int
	bind_owner(&owner)
	defer unbind_owner()
	testing.expect(t, owner_for_thread() == rawptr(&owner))
	cancel_request(&owner)
	defer cancel_clear(&owner)
	testing.expect(t, cancel_requested())
	testing.expect(t, cancel_requested(&owner))
}

@(test)
test_cancel_unbound_thread_safe :: proc(t: ^testing.T) {
	// No binding on this thread (tests share threads): never cancelled.
	testing.expect(t, !cancel_requested())
	testing.expect(t, !cancel_requested(nil))
}
