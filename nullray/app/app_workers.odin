// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Join/clear helpers for App-owned background worker threads.
*/

package app

import "core:thread"
import "core:time"

@(private)
app_join_worker :: proc(th: ^^thread.Thread, wait_ms: int) -> bool {
	if th^ == nil {
		return true
	}
	deadline := time.tick_now()
	limit := time.Millisecond * time.Duration(wait_ms)
	for !thread.is_done(th^) {
		if time.tick_since(deadline) > limit {
			return false
		}
		time.sleep(5 * time.Millisecond)
	}
	thread.join(th^)
	thread.destroy(th^)
	th^ = nil
	return true
}

