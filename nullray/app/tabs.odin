// SPDX-License-Identifier: 0BSD
/*
Session tabs: multiple live sessions behind a top strip. Each tab owns a
heap Session so its chat worker keeps running while another tab is active.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:store"
import "nullray:subagent"
import "nullray:ui"

TAB_MAX :: 16
TAB_LABEL_MAX :: 18

Tab :: struct {
	sess:         ^session.Session,
	done_pending: bool,
	busy_before:  bool,
}

// Click region for a tab label, filled during draw.
Tab_Hit :: struct {
	i:  int,
	x0: int,
	x1: int,
}

app_session_alloc :: proc(a: ^App) -> ^session.Session {
	s := new(session.Session)
	session.session_init(s)
	s.tools_registry = &a.tools_reg
	if a.session != nil && len(a.session.model) > 0 {
		// New tabs inherit the active provider/model.
		delete(s.model)
		s.model = strings.clone(a.session.model)
		delete(s.provider_id)
		s.provider_id = strings.clone(a.session.provider_id)
	} else {
		_ = session.session_apply_saved_model(s, &a.registry)
		session.session_sticky_auto_provider(s, &a.registry)
	}
	session.session_rebuild_system_prompt(s)
	return s
}

app_tab_bind_active :: proc(a: ^App) {
	a.session = a.tabs[a.active_tab].sess
	a.tabs[a.active_tab].done_pending = false
	provider.set_session(a.session.name)
	subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
	// Queued attachments belong to the composer; do not smuggle them into
	// another session's next prompt.
	app_media_clear(a)
	a.scroll = 0
	a.follow = true
	app_mark_dirty(a)
}

app_tab_goto :: proc(a: ^App, i: int) {
	if i < 0 || i >= len(a.tabs) || i == a.active_tab {
		return
	}
	a.active_tab = i
	app_tab_bind_active(a)
}

app_tab_cycle :: proc(a: ^App, delta: int) {
	n := len(a.tabs)
	if n < 2 {
		return
	}
	i := ((a.active_tab + delta) % n + n) % n
	app_tab_goto(a, i)
}

app_tab_new :: proc(a: ^App, name: string) {
	if len(a.tabs) >= TAB_MAX {
		session.session_set_status(a.session, "tab limit reached")
		return
	}
	s := app_session_alloc(a)
	// Every tab needs its own session path: session_init always binds the
	// shared default path, which would interleave transcripts between tabs.
	if !session.session_new(s, strings.trim_space(name)) {
		session.session_destroy(s)
		free(s)
		return
	}
	append(&a.tabs, Tab{sess = s})
	a.active_tab = len(a.tabs) - 1
	app_tab_bind_active(a)
	app_tabs_persist(a)
}

// Open a saved session in its own tab (or jump to the tab that has it).
app_tab_open_named :: proc(a: ^App, name: string) {
	safe := store.sanitize_name(name)
	for t, i in a.tabs {
		if t.sess.name == safe {
			app_tab_goto(a, i)
			session.session_set_status(a.session, fmt.tprintf("tab %d: %s", i + 1, safe))
			return
		}
	}
	if len(a.tabs) >= TAB_MAX {
		session.session_set_status(a.session, "tab limit reached")
		return
	}
	s := app_session_alloc(a)
	if !session.session_switch(s, name) {
		session.session_destroy(s)
		free(s)
		return
	}
	append(&a.tabs, Tab{sess = s})
	a.active_tab = len(a.tabs) - 1
	app_tab_bind_active(a)
	app_tabs_persist(a)
}

app_tab_close :: proc(a: ^App, i: int) {
	if i < 0 || i >= len(a.tabs) {
		return
	}
	if len(a.tabs) <= 1 {
		session.session_set_status(a.session, "last tab stays open")
		return
	}
	t := a.tabs[i]
	if t.sess.busy {
		session.session_request_cancel(t.sess)
		session.session_shutdown(t.sess)
		if t.sess.busy {
			// Worker did not join before the wait cap. Freeing the session
			// while it writes would corrupt memory, so keep the tab.
			session.session_set_status(
				a.session,
				"session still stopping · run /tab close again",
			)
			return
		}
	}
	session.session_shutdown(t.sess)
	session.session_destroy(t.sess)
	free(t.sess)
	ordered_remove(&a.tabs, i)
	if a.active_tab >= len(a.tabs) {
		a.active_tab = len(a.tabs) - 1
	} else if i < a.active_tab {
		a.active_tab -= 1
	}
	app_tab_bind_active(a)
	app_tabs_persist(a)
}

app_tab_active_index :: proc(a: ^App, s: ^session.Session) -> int {
	for t, i in a.tabs {
		if t.sess == s {
			return i
		}
	}
	return -1
}

// Poll every tab so background workers drain events into their transcripts.
app_poll_tabs :: proc(a: ^App) -> bool {
	changed := false
	for t, i in a.tabs {
		if session.session_poll(t.sess) {
			changed = true
		}
		if t.busy_before && !t.sess.busy {
			if i != a.active_tab {
				a.tabs[i].done_pending = true
			}
			changed = true
		}
		if t.sess.busy != t.busy_before {
			a.tabs[i].busy_before = t.sess.busy
			changed = true
		}
	}
	return changed
}

// Hit-test the strip using the boxes recorded by the last draw.
app_tab_hit :: proc(a: ^App, mx: int) -> int {
	for h in a.tab_hits {
		if mx >= h.x0 && mx < h.x1 {
			return h.i
		}
	}
	return -1
}

// Ctrl-X prefix: opencode-style chords for tab control.
app_tab_prefix_key :: proc(a: ^App, ev: ui.Event) {
	handled := true
	#partial switch ev.kind {
	case .Left:
		app_tab_cycle(a, -1)
	case .Right:
		app_tab_cycle(a, 1)
	case .Rune:
		switch ev.ch {
		case 'n':
			app_tab_new(a, "")
		case 'w':
			app_tab_close(a, a.active_tab)
		case 'h':
			app_tab_cycle(a, -1)
		case 'l':
			app_tab_cycle(a, 1)
		case 'o':
			slash_cmd_sessions(a, "")
		case '1' ..= '9':
			app_tab_goto(a, int(ev.ch - '1'))
		case:
			handled = false
		}
	case:
		handled = false
	}
	if !handled {
		session.session_set_status(a.session, "tab prefix cancelled")
	}
}

app_tabs_any_busy :: proc(a: ^App) -> bool {
	for t in a.tabs {
		if t.sess.busy {
			return true
		}
	}
	return false
}

@(private)
tabs_state_path :: proc(allocator := context.allocator) -> string {
	dir := sandbox.resolve_config_dir(context.temp_allocator)
	p, _ := filepath.join({dir, "open_tabs"}, allocator)
	return p
}

// Persist open tab names so the strip survives restarts.
app_tabs_persist :: proc(a: ^App) {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%d\n", a.active_tab)
	for t in a.tabs {
		strings.write_string(&b, t.sess.name)
		strings.write_byte(&b, '\n')
	}
	_ = os.write_entire_file(tabs_state_path(), transmute([]u8)strings.to_string(b))
}

// Restore open tabs from the last run. Names that no longer resolve are
// skipped; the caller falls back to one fresh tab when nothing restored.
app_tabs_restore :: proc(a: ^App) {
	if v, ok := os.lookup_env(constants.ENV_SESSION, context.temp_allocator); ok {
		// An explicit session selection wins over the saved strip.
		if len(v) > 0 && v != "on" && v != "1" && v != "true" {
			return
		}
	}
	data, err := os.read_entire_file(tabs_state_path(), context.temp_allocator)
	if err != nil {
		return
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	active := 0
	start := 0
	if len(lines) > 0 {
		if n, ok := strconv.parse_int(strings.trim_space(lines[0])); ok {
			active = n
			start = 1
		}
	}
	for line in lines[start:] {
		name := strings.trim_space(line)
		if len(name) == 0 || len(a.tabs) >= TAB_MAX {
			continue
		}
		dup := false
		for t in a.tabs {
			if t.sess.name == name {
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		s := app_session_alloc(a)
		if !session.session_switch(s, name) {
			session.session_destroy(s)
			free(s)
			continue
		}
		append(&a.tabs, Tab{sess = s})
	}
	if len(a.tabs) == 0 {
		return
	}
	if active < 0 || active >= len(a.tabs) {
		active = 0
	}
	a.active_tab = active
}

@(private)
tab_label :: proc(name: string) -> string {
	if len(name) == 0 {
		return "default"
	}
	if ui.string_cols(name) > TAB_LABEL_MAX {
		return fmt.tprintf("%.*s…", TAB_LABEL_MAX - 1, name)
	}
	return name
}

// Display width of one strip cell: indicator + label + space + separator.
@(private)
tab_cell_w :: proc(name: string) -> int {
	return min(ui.string_cols(name), TAB_LABEL_MAX) + 3
}

// Horizontal strip at row y: busy tabs spin, finished-away tabs flag done,
// a trailing + opens a new tab, and ‹/› mark scroll overflow. The window
// scrolls to keep the active tab visible.
app_draw_tabs :: proc(buf: ^ui.Buffer, a: ^App, y: int) {
	t := ui.theme()
	clear(&a.tab_hits)
	a.tab_plus_x = -1
	n := len(a.tabs)
	if n == 0 {
		return
	}
	if a.tab_scroll > a.active_tab {
		a.tab_scroll = a.active_tab
	}
	if a.tab_scroll >= n {
		a.tab_scroll = n - 1
	}
	scroll := max(a.tab_scroll, 0)

	PLUS_W :: 4 // " +" plus separator room
	EDGE_W :: 2 // "‹ " or " ›"
	avail := max(buf.width - 1 - PLUS_W, 4)

	// Advance the window until the active tab is visible.
	for scroll < a.active_tab {
		lmark := scroll > 0 ? EDGE_W : 0
		x := lmark
		i := scroll
		for i < n {
			rmark := i < n - 1 ? EDGE_W : 0
			w := tab_cell_w(a.tabs[i].sess.name)
			if x + w + rmark > avail {
				break
			}
			x += w
			i += 1
		}
		if a.active_tab < i {
			break
		}
		scroll += 1
	}
	a.tab_scroll = scroll

	x := 0
	ui.buffer_text(buf, x, y, " ", t.muted, t.status_bg)
	x += 1
	if scroll > 0 {
		ui.buffer_text(buf, x, y, "‹", t.muted, t.status_bg)
		x += EDGE_W
	}
	for i := scroll; i < n; i += 1 {
		tab := a.tabs[i]
		label := tab_label(tab.sess.name)
		indicator := " "
		if tab.sess.busy {
			indicator = ui.spinner_frame(&a.spinner)
		} else if tab.done_pending {
			indicator = "●"
		}
		w := ui.string_cols(label) + 3
		rmark := i < n - 1 ? EDGE_W : 0
		if x + w + rmark > buf.width - PLUS_W {
			ui.buffer_text(buf, x, y, "›", t.muted, t.status_bg)
			x += EDGE_W
			break
		}
		fg := t.muted
		bg := t.status_bg
		style: ui.Style
		if i == a.active_tab {
			fg = t.accent
			style = {.Bold}
		} else if tab.sess.busy || tab.done_pending {
			fg = t.accent
		}
		text := fmt.tprintf("%s%s ", indicator, label)
		append(&a.tab_hits, Tab_Hit{i = i, x0 = x, x1 = x + w})
		ui.buffer_text(buf, x, y, text, fg, bg, style)
		x += ui.string_cols(text)
		ui.buffer_text(buf, x, y, "│", t.border, t.status_bg)
		x += 1
	}
	plus_fg := t.accent
	if n >= TAB_MAX {
		plus_fg = t.muted
	}
	a.tab_plus_x = x
	ui.buffer_text(buf, x, y, " +", plus_fg, t.status_bg, {.Bold})
	x += 2
	for x < buf.width {
		ui.buffer_put(buf, x, y, ' ', t.fg, t.status_bg, {})
		x += 1
	}
}
