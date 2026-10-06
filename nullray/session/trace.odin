// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Print-mode observability: --trace writes one compact stderr line per tool
call (start with the activity line, done with elapsed seconds and the
exit_code when the result carries one), and --stream mirrors assistant
deltas to stdout as they arrive so pipes see live output.
*/

package session

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

TRACE_SLOTS :: 32

Trace_Slot :: struct {
	name: string, // heap clone, owned by the session until destroy
	tick: time.Tick,
}

trace_from_env :: proc() -> bool {
	if v, ok := os.lookup_env("NULLRAY_TRACE", context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

stream_print_from_env :: proc() -> bool {
	if v, ok := os.lookup_env("NULLRAY_PRINT_STREAM", context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

/*
Trace line on tool start: "nullray: <activity line>". Start ticks live in a
fixed slot table (a dynamic map would need careful key ownership across the
worker thread; 32 parallel tool names is far above any fan-out we do).
*/
session_trace_start :: proc(s: ^Session, name, activity: string) {
	if s == nil || !s.trace {
		return
	}
	if s.trace_starts == nil {
		s.trace_starts = make([]Trace_Slot, TRACE_SLOTS, runtime.heap_allocator())
	}
	slot: ^Trace_Slot
	free_slot: ^Trace_Slot
	for &sl in s.trace_starts {
		if sl.name == name {
			slot = &sl
			break
		}
		if len(sl.name) == 0 && free_slot == nil {
			free_slot = &sl
		}
	}
	if slot == nil {
		slot = free_slot
		if slot != nil {
			slot.name = strings.clone(name, runtime.heap_allocator())
		}
	}
	if slot != nil {
		slot.tick = time.tick_now()
	}
	fmt.eprintf("nullray: %s\n", activity)
}

// Slice out "exit_code=N" when the tool result leads with it (shell, script
// tools). Borrowed, empty when absent - no allocation, so the caller never
// has to free it.
@(private)
trace_exit_code :: proc(text: string) -> string {
	if !strings.has_prefix(text, "exit_code=") {
		return ""
	}
	end := strings.index_byte(text, '\n')
	if end < 0 {
		end = len(text)
	}
	return text[:end]
}

session_trace_done :: proc(s: ^Session, name, result_text: string) {
	if s == nil || !s.trace {
		return
	}
	elapsed := ""
	if s.trace_starts != nil {
		for &sl in s.trace_starts {
			if sl.name == name {
				elapsed = fmt.tprintf(" %.2fs", time.duration_seconds(time.tick_since(sl.tick)))
				break
			}
		}
	}
	extra := trace_exit_code(result_text)
	if len(extra) > 0 {
		fmt.eprintf("nullray: %s %s%s\n", name, extra, elapsed)
	} else {
		fmt.eprintf("nullray: %s done%s\n", name, elapsed)
	}
}

session_trace_destroy :: proc(s: ^Session) {
	if s.trace_starts == nil {
		return
	}
	for &sl in s.trace_starts {
		delete(sl.name, runtime.heap_allocator())
	}
	delete(s.trace_starts, runtime.heap_allocator())
	s.trace_starts = nil
}

// Mirror an assistant delta to stdout for --stream. Runs on the chat
// worker; writes are small enough to interleave harmlessly with stderr.
session_stream_delta :: proc(s: ^Session, text: string) {
	if s == nil || !s.stream_stdout || len(text) == 0 {
		return
	}
	n, _ := os.write(os.stdout, transmute([]u8)text)
	if n > 0 {
		s.streamed_chars += n
	}
}
