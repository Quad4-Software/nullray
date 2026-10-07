// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package agent

import "nullray:experience"

run_turn :: proc(req: Run_Request, cfg: Config, allocator := context.allocator) -> Run_Result {
	res := run_turn_inner(req, cfg, allocator)
	if len(cfg.session_id) > 0 {
		experience.exp_record_turn(
			req.messages, res.messages[:],
			res.ok, res.stopped, res.err, res.content, res.escalations,
		)
	}
	return res
}
