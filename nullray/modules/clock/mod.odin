// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Example module. Dropping this directory under nullray/modules/ is enough:
scripts/gen_modules.py adds a side-effect import at build time and the
@(init) registers the contribution. Remove the directory and rebuild to
uninstall. See docs/modules.md.
*/

package clock

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "nullray:modules"

@(init)
clock_init :: proc "contextless" () {
	// Init procs are contextless; install a context before building any
	// literals (slices allocate from context.allocator).
	context = runtime.default_context()
	modules.modules_register(modules.Module{
		id = "clock",
		name = "Clock",
		version = "0.1.0",
		description = "current time tool and /time command",
		tools = []modules.Tool_Spec{{
			name = "get_time",
			description = "Return the current UTC time",
			schema_json = `{"type":"object","properties":{"format":{"type":"string","description":"rfc3339 or epoch"}},"required":[]}`,
			kind = .Read,
			run = tool_get_time,
		}},
		commands = []modules.Command_Spec{{
			name = "time",
			help = "what time is it",
			prompt = "Call get_time and answer plainly.",
		}},
	})
}

tool_get_time :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	now := time.now()
	epoch := time.to_unix_nanoseconds(now) / 1_000_000_000
	y, mon, d := time.date(now)
	h, mi, sec := time.clock(now)
	return fmt.aprintf(
		"%04d-%02d-%02dT%02d:%02d:%02dZ (epoch %d)",
		y, int(mon), d, h, mi, sec, epoch,
		allocator = allocator,
	), ""
}
