// SPDX-License-Identifier: 0BSD
/*
Architect subagent type helpers (no agent import: avoid cycles).
*/

package subagent

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

architect_steps_from_env :: proc() -> int {
	n := 6
	if v, ok := os.lookup_env(constants.ENV_ARCHITECT_STEPS, context.temp_allocator); ok {
		if parsed, pok := strconv.parse_int(strings.trim_space(v)); pok {
			n = parsed
		}
	}
	if n < 1 {
		n = 1
	}
	if n > constants.MAX_ARCHITECT_STEPS {
		n = constants.MAX_ARCHITECT_STEPS
	}
	return n
}

is_architect_type :: proc(type_name: string) -> bool {
	low := strings.to_lower(strings.trim_space(type_name), context.temp_allocator)
	return low == "architect" || low == "architect-agent"
}
