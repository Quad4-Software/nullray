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
	trimmed := strings.trim_space(name)
	if len(trimmed) > 0 && !session.session_new(s, trimmed) {
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

// Columns mirror app_draw_tabs: one indicator + label + trailing space + separator.
app_tab_at_x :: proc(a: ^App, mx: int) -> int {
	x := 1
	for tab, i in a.tabs {
		label := tab.sess.name
		if len(label) == 0 {
			label = "default"
		}
		cols := ui.string_cols(label)
		if cols > TAB_LABEL_MAX {
			cols = TAB_LABEL_MAX
		}
		w := cols + 3
		if mx >= x && mx < x + w {
			return i
		}
		x += w
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
			slash_cmd_tab(a, "")
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

// Horizontal strip at row y: busy tabs spin, finished-away tabs flag done.
app_draw_tabs :: proc(buf: ^ui.Buffer, a: ^App, y: int) {
	t := ui.theme()
	x := 0
	if x >= buf.width {
		return
	}
	ui.buffer_text(buf, x, y, " ", t.muted, t.status_bg)
	x += 1
	for tab, i in a.tabs {
		if x >= buf.width - 4 {
			ui.buffer_text(buf, x, y, "…", t.muted, t.status_bg)
			x += 2
			break
		}
		label := tab.sess.name
		if len(label) == 0 {
			label = "default"
		}
		if ui.string_cols(label) > TAB_LABEL_MAX {
			label = fmt.tprintf("%.*s…", TAB_LABEL_MAX - 1, label)
		}
		indicator := " "
		if tab.sess.busy {
			indicator = ui.spinner_frame(&a.spinner)
		} else if tab.done_pending {
			indicator = "●"
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
		ui.buffer_text(buf, x, y, text, fg, bg, style)
		x += ui.string_cols(text)
		ui.buffer_text(buf, x, y, "│", t.border, t.status_bg)
		x += 1
	}
	for x < buf.width {
		ui.buffer_put(buf, x, y, ' ', t.fg, t.status_bg, {})
		x += 1
	}
}
