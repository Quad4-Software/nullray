// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Ticker thread and the env-driven heartbeat job.

Every WATCH_TICK_MS the watcher resolves due jobs and emits each one through
the wakeup sink registered by the app. The heartbeat is not a stored job: it
lives only in this tick, is inert when HEARTBEAT_FILE is missing, never
fires while the session is busy, and coalesces to a single queued wakeup.
*/

package schedule

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"

WATCH_TICK_MS :: 5000
WATCH_SLICE_MS :: 100
HEARTBEAT_TAG :: "heartbeat"

HEARTBEAT_PROMPT :: "Heartbeat: read the checklist at .nullray/HEARTBEAT.md and act on anything that needs attention. If nothing needs attention, reply exactly: HEARTBEAT_OK"

g_watch_mu:     sync.Mutex
g_watch_stop:   bool
g_watch_thread: ^thread.Thread

g_hb_enabled:  bool
g_hb_allowed:  bool = true
g_hb_interval: i64
g_hb_next:     i64
g_hb_queued:   bool

unix_now :: proc() -> i64 {
	return time.time_to_unix(time.now())
}

// NULLRAY_HEARTBEAT: 0/off disables, bare seconds or a duration sets the
// interval, 1/on/auto selects the default. Unset means disabled.
heartbeat_interval_from_env :: proc() -> i64 {
	v, ok := os.lookup_env(constants.ENV_HEARTBEAT, context.temp_allocator)
	if !ok {
		return 0
	}
	s := strings.to_lower(strings.trim_space(v), context.temp_allocator)
	switch s {
	case "", "0", "off", "false", "no":
		return 0
	case "1", "on", "auto", "true", "yes":
		return constants.HEARTBEAT_DEFAULT_SEC
	}
	if n, n_ok := strconv.parse_i64(s); n_ok {
		return max(n, 0)
	}
	if d, d_ok := dur_parse(s); d_ok {
		return d
	}
	return 0
}

schedule_set_heartbeat_allowed :: proc(allowed: bool) {
	g_hb_allowed = allowed
}

// Called under g_jobs_mu from schedule_tick. Skips the beat (and re-arms)
// when the session is busy or no checklist exists.
heartbeat_tick :: proc(now: i64, due: ^[dynamic]Due, allocator := context.allocator) {
	if !g_hb_enabled || !g_hb_allowed || g_hb_interval <= 0 {
		return
	}
	if now < g_hb_next {
		return
	}
	g_hb_next = now + g_hb_interval
	if g_hb_queued {
		if wakeup_still_queued(HEARTBEAT_TAG, "") {
			return
		}
		g_hb_queued = false
	}
	if g_busy != nil && g_busy() {
		return
	}
	if !heartbeat_file_exists() {
		return
	}
	append(due, Due{
		id = 0,
		tag = strings.clone(HEARTBEAT_TAG, allocator),
		prompt = strings.clone(HEARTBEAT_PROMPT, allocator),
		kind = .Heartbeat,
	})
	g_hb_queued = true
}

@(private)
heartbeat_file_exists :: proc() -> bool {
	ws := workspace_root(context.temp_allocator)
	path, _ := filepath.join({ws, constants.HEARTBEAT_FILE}, context.temp_allocator)
	_, err := os.stat(path, context.temp_allocator)
	return err == nil
}

// One-line heartbeat summary for /schedule list.
heartbeat_status :: proc(allocator := context.allocator) -> string {
	if !g_hb_enabled || !g_hb_allowed || g_hb_interval <= 0 {
		return ""
	}
	in_sec := g_hb_next - unix_now()
	if in_sec < 0 {
		in_sec = 0
	}
	state := "armed"
	if !heartbeat_file_exists() {
		state = "inert (no .nullray/HEARTBEAT.md)"
	}
	return fmt.aprintf(
		"heartbeat: every %s | next in %s | %s\n",
		fmt_delta(g_hb_interval, context.temp_allocator),
		fmt_delta(in_sec, context.temp_allocator),
		state,
		allocator = allocator,
	)
}

schedule_start :: proc() {
	if !schedule_enabled() {
		return
	}
	jobs_ensure_init()
	sync.mutex_lock(&g_watch_mu)
	if g_watch_thread != nil {
		sync.mutex_unlock(&g_watch_mu)
		return
	}
	g_hb_interval = heartbeat_interval_from_env()
	g_hb_enabled = g_hb_interval > 0
	g_hb_queued = false
	g_hb_next = unix_now() + g_hb_interval
	g_watch_stop = false
	th := thread.create_and_start_with_data(nil, schedule_watch_main)
	g_watch_thread = th
	sync.mutex_unlock(&g_watch_mu)
}

schedule_stop :: proc() {
	sync.mutex_lock(&g_watch_mu)
	g_watch_stop = true
	th := g_watch_thread
	sync.mutex_unlock(&g_watch_mu)
	if th == nil {
		return
	}
	thread.join(th)
	thread.destroy(th)
	sync.mutex_lock(&g_watch_mu)
	g_watch_thread = nil
	sync.mutex_unlock(&g_watch_mu)
}

@(private)
watch_should_stop :: proc() -> bool {
	sync.mutex_lock(&g_watch_mu)
	stop := g_watch_stop
	sync.mutex_unlock(&g_watch_mu)
	return stop
}

schedule_watch_main :: proc(_: rawptr) {
	for {
		// Slice the tick so schedule_stop joins promptly.
		for _ in 0 ..< WATCH_TICK_MS / WATCH_SLICE_MS {
			if watch_should_stop() {
				return
			}
			time.sleep(time.Duration(WATCH_SLICE_MS) * time.Millisecond)
		}
		// External durable-store edits (watch add/rm from another nullray
		// process) merge before the tick so due resolution sees them.
		jobs_reload_if_changed()
		due := schedule_tick(unix_now())
		for d in due {
			emit_due(d)
		}
		due_list_destroy(due)
	}
}
