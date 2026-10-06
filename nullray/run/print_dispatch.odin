// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Print-mode entry: env for --samples/--architect, then one inner run.
Nested sample and architect calls skip this so they cannot recurse.
*/

package run

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

run_print :: proc(cfg: Config) -> Result {
	cfg := cfg
	if cfg.samples == 0 {
		if v, ok := os.lookup_env(constants.ENV_SAMPLES, context.temp_allocator); ok {
			if n, nok := strconv.parse_int(strings.trim_space(v)); nok && n > 1 {
				cfg.samples = n
			}
		}
	}
	if !cfg.architect {
		if v, ok := os.lookup_env(constants.ENV_ARCHITECT, context.temp_allocator); ok {
			switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
			case "1", "true", "yes", "on":
				cfg.architect = true
			}
		}
	}
	if cfg.samples > 1 {
		return run_samples(cfg)
	}
	if cfg.architect {
		return run_architect_print(cfg)
	}
	return run_print_inner(cfg)
}
