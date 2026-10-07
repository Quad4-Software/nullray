// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Print peak RSS (kB) of a child process. Polls /proc/<pid>/status VmHWM
while the child runs. Used by bench-gates.sh so the bench suite needs no
python or GNU time. Linux only; callers fall back to time -l elsewhere.

Run: odin run scripts/rss_probe.odin -file -- ./bin/nullray --self-test
*/

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

main :: proc() {
	when ODIN_OS != .Linux {
		fmt.eprintln("rss_probe: linux only")
		os.exit(2)
	}
	if len(os.args) < 2 {
		fmt.eprintln("usage: rss_probe <cmd> [args...]")
		os.exit(2)
	}

	child, perr := os.process_start({
		command = os.args[1:],
		stdout = nil,
		stderr = nil,
	})
	if perr != nil {
		fmt.eprintln("rss_probe: spawn failed:", perr)
		os.exit(2)
	}

	peak := 0
	status_path := fmt.aprintf("/proc/%d/status", child.pid, allocator = context.temp_allocator)
	for {
		if data, err := os.read_entire_file(status_path, context.temp_allocator); err == nil {
			for line in strings.split(string(data), "\n", context.temp_allocator) {
				if strings.has_prefix(line, "VmHWM:") {
					f := strings.trim_suffix(strings.trim_space(line[len("VmHWM:"):]), " kB")
					if v, ok := strconv.parse_int(strings.trim_space(f)); ok && v > peak {
						peak = v
					}
				}
			}
		}
		state, werr := os.process_wait(child, 5 * time.Millisecond)
		if werr == nil && state.exited {
			break
		}
	}
	fmt.println(peak)
}
