// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package run

import "core:testing"

@(test)
test_sample_score_prefers_clean_done :: proc(t: ^testing.T) {
	a := Result{exit_code = 0, stopped = "done"}
	b := Result{exit_code = 1, stopped = "done"}
	c := Result{exit_code = 1, stopped = "verify_failed"}
	testing.expect(t, sample_score(a) > sample_score(b))
	testing.expect(t, sample_score(b) > sample_score(c))
}
