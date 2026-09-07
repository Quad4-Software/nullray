// SPDX-License-Identifier: 0BSD
/*
Subagent enable/disable, concurrent max, and depth from env and session.
*/

package subagent

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Limits :: struct {
	enabled:   bool,
	max:       int,
	depth:     int,
	steps:     int,
	session_off: bool,
	cli_off:     bool,
}

limits_from_env :: proc() -> Limits {
	lim := Limits{
		enabled = true,
		max = constants.DEFAULT_SUBAGENT_MAX,
		depth = constants.DEFAULT_SUBAGENT_DEPTH,
		steps = 0,
	}
	if v, ok := os.lookup_env(constants.ENV_SUBAGENTS, context.temp_allocator); ok {
		trimmed := strings.trim_space(v)
		low := strings.to_lower(trimmed, context.temp_allocator)
		if low == "0" || low == "off" || low == "false" || low == "no" || low == "disable" {
			lim.enabled = false
			lim.max = 0
		} else if n, nok := strconv.parse_int(trimmed); nok {
			if n <= 0 {
				lim.enabled = false
				lim.max = 0
			} else {
				lim.max = n
			}
		}
	}
	if v, ok := os.lookup_env(constants.ENV_SUBAGENT_DEPTH, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(strings.trim_space(v)); nok && n >= 0 {
			lim.depth = n
		}
	}
	if v, ok := os.lookup_env(constants.ENV_SUBAGENT_STEPS, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(strings.trim_space(v)); nok && n > 0 {
			lim.steps = n
		}
	}
	return lim
}

teams_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SUBAGENT_TEAMS, context.temp_allocator); ok {
		low := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		return low == "1" || low == "true" || low == "on" || low == "yes"
	}
	return false
}

effective_enabled :: proc(lim: Limits) -> bool {
	if lim.cli_off || lim.session_off {
		return false
	}
	return lim.enabled && lim.max > 0
}
