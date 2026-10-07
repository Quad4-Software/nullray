// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Side pane file viewer: open, recent list, strip hits, scroll.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:session"
import "nullray:tools"

VIEW_RECENT_MAX :: 16
VIEW_MIN_PANE :: 28
VIEW_MIN_TRANSCRIPT :: 40
VIEW_SPLIT_MIN_WIDTH :: 72

View_Layout :: struct {
	open:     bool,
	overlay:  bool,
	split_x:  int,
	pane_x:   int,
	pane_w:   int,
	pane_y:   int,
	pane_h:   int,
}

// Click region for one recent-file label, filled during draw.
View_Strip_Hit :: struct {
	i:  int,
	x0: int,
	x1: int,
}

// Index of the strip label under column mx, or -1 for gaps and misses.
view_strip_hit :: proc(hits: []View_Strip_Hit, mx: int) -> int {
	for h in hits {
		if mx >= h.x0 && mx < h.x1 {
			return h.i
		}
	}
	return -1
}

// Digit count of the largest line number, minimum 1.
view_num_w :: proc(total: int) -> int {
	w := 1
	for n := max(1, total); n >= 10; n /= 10 {
		w += 1
	}
	return w
}

// Wrapped target index for recent-file cycling, or -1 when empty.
view_nav_idx :: proc(cur, delta, n: int) -> int {
	if n <= 0 {
		return -1
	}
	idx := (cur + delta) % n
	if idx < 0 {
		idx += n
	}
	return idx
}

app_view_clear_recent :: proc(a: ^App) {
	for p in a.view_recent {
		delete(p)
	}
	clear(&a.view_recent)
	a.view_idx = 0
}

app_view_close :: proc(a: ^App) {
	delete(a.view_path)
	delete(a.view_body)
	a.view_path = ""
	a.view_body = ""
	a.view_open = false
	a.view_focus = false
	a.view_scroll = 0
	a.view_err = false
	a.view_strip_y = -1
	clear(&a.view_strip_hits)
	app_view_clear_recent(a)
	app_mark_dirty(a)
}

app_view_destroy :: proc(a: ^App) {
	delete(a.view_path)
	delete(a.view_body)
	a.view_path = ""
	a.view_body = ""
	app_view_clear_recent(a)
	delete(a.view_strip_hits)
	a.view_open = false
	a.view_focus = false
	a.view_scroll = 0
	a.view_err = false
	a.view_strip_y = -1
}

@(private)
app_view_push_recent :: proc(a: ^App, abs_path: string) {
	for i in 0 ..< len(a.view_recent) {
		if a.view_recent[i] == abs_path {
			old := a.view_recent[i]
			ordered_remove(&a.view_recent, i)
			append(&a.view_recent, old)
			a.view_idx = len(a.view_recent) - 1
			return
		}
	}
	append(&a.view_recent, strings.clone(abs_path))
	for len(a.view_recent) > VIEW_RECENT_MAX {
		delete(a.view_recent[0])
		ordered_remove(&a.view_recent, 0)
	}
	a.view_idx = len(a.view_recent) - 1
}

app_view_set_recent :: proc(a: ^App, paths: []string) {
	app_view_clear_recent(a)
	for p in paths {
		if len(p) == 0 {
			continue
		}
		dup := false
		for existing in a.view_recent {
			if existing == p {
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		append(&a.view_recent, strings.clone(p))
		if len(a.view_recent) >= VIEW_RECENT_MAX {
			break
		}
	}
	if len(a.view_recent) > 0 {
		a.view_idx = len(a.view_recent) - 1
	}
}

// Show a load failure as a pane row instead of leaving stale or blank content.
@(private)
app_view_fail :: proc(a: ^App, abs_path: string) {
	delete(a.view_body)
	a.view_body = ""
	delete(a.view_path)
	a.view_path = strings.clone(abs_path)
	a.view_err = true
	a.view_scroll = 0
	a.view_open = true
	app_mark_dirty(a)
}

@(private)
app_view_load_body :: proc(a: ^App, abs_path: string) -> bool {
	if sandbox.path_is_secret_blocked(abs_path) {
		session.session_set_status(a.session, "secret file blocked")
		app_view_fail(a, abs_path)
		return false
	}
	if !sandbox.path_allowed(sandbox.state(), abs_path, false) {
		session.session_set_status(a.session, "path not allowed for read")
		app_view_fail(a, abs_path)
		return false
	}
	data, err := os.read_entire_file(abs_path, context.allocator)
	if err != nil {
		session.session_set_status(a.session, "view read failed")
		app_view_fail(a, abs_path)
		return false
	}
	text := string(data)
	if len(text) > constants.MAX_READ_FILE_CHARS {
		trimmed := strings.clone(text[:constants.MAX_READ_FILE_CHARS])
		delete(data)
		note := fmt.tprintf("\n\n[truncated at %d chars]", constants.MAX_READ_FILE_CHARS)
		combined := strings.concatenate({trimmed, note})
		delete(trimmed)
		delete(a.view_body)
		a.view_body = combined
	} else {
		delete(a.view_body)
		a.view_body = text
	}
	delete(a.view_path)
	a.view_path = strings.clone(abs_path)
	a.view_err = false
	a.view_scroll = 0
	a.view_open = true
	return true
}

app_view_open :: proc(a: ^App, path: string) -> bool {
	trimmed := strings.trim_space(path)
	if len(trimmed) == 0 {
		return false
	}
	abs := tools.resolve_path(trimmed, context.temp_allocator)
	if !app_view_load_body(a, abs) {
		return false
	}
	app_view_push_recent(a, a.view_path)
	base := filepath.base(a.view_path)
	if len(a.view_recent) > 1 {
		session.session_set_status(
			a.session,
			fmt.tprintf("view: %s (%d/%d)", base, a.view_idx + 1, len(a.view_recent)),
		)
	} else {
		session.session_set_status(a.session, fmt.tprintf("view: %s", base))
	}
	app_mark_dirty(a)
	return true
}

app_view_open_text :: proc(a: ^App, title: string, body: string) -> bool {
	if a == nil || len(body) == 0 {
		return false
	}
	delete(a.view_path)
	delete(a.view_body)
	a.view_path = strings.clone(title)
	a.view_body = strings.clone(body)
	a.view_err = false
	a.view_scroll = 0
	a.view_open = true
	a.view_focus = true
	session.session_set_status(a.session, fmt.tprintf("view: %s", title))
	app_mark_dirty(a)
	return true
}

app_view_reload :: proc(a: ^App) -> bool {
	if !a.view_open || len(a.view_path) == 0 {
		return false
	}
	path := strings.clone(a.view_path)
	defer delete(path)
	ok := app_view_load_body(a, path)
	if ok {
		app_mark_dirty(a)
	}
	return ok
}

// Open view_recent[idx] in the pane. Used by strip clicks and key nav.
// On load failure the pane shows a "cannot open" row for that path.
app_view_open_idx :: proc(a: ^App, idx: int) -> bool {
	if idx < 0 || idx >= len(a.view_recent) {
		return false
	}
	a.view_idx = idx
	ok := app_view_load_body(a, a.view_recent[idx])
	if ok {
		base := filepath.base(a.view_path)
		n := len(a.view_recent)
		if n > 1 {
			session.session_set_status(
				a.session,
				fmt.tprintf("view: %s (%d/%d)", base, a.view_idx + 1, n),
			)
		} else {
			session.session_set_status(a.session, fmt.tprintf("view: %s", base))
		}
	}
	app_mark_dirty(a)
	return ok
}

app_view_switch :: proc(a: ^App, delta: int) {
	n := len(a.view_recent)
	if n <= 1 || !a.view_open {
		return
	}
	idx := view_nav_idx(a.view_idx, delta, n)
	if idx < 0 || idx == a.view_idx {
		return
	}
	app_view_open_idx(a, idx)
}

app_view_layout :: proc(a: ^App, width, height: int) -> View_Layout {
	lay: View_Layout
	if !a.view_open || a.show_help {
		return lay
	}
	lay.open = true
	lay.pane_y = 2
	lay.pane_h = max(1, height - 5)
	if width >= VIEW_SPLIT_MIN_WIDTH {
		pane_w := max(VIEW_MIN_PANE, width * 2 / 5)
		if width - pane_w - 1 < VIEW_MIN_TRANSCRIPT {
			pane_w = width - VIEW_MIN_TRANSCRIPT - 1
		}
		if pane_w >= VIEW_MIN_PANE && width - pane_w - 1 >= VIEW_MIN_TRANSCRIPT {
			lay.split_x = width - pane_w - 1
			lay.pane_x = lay.split_x + 1
			lay.pane_w = pane_w
			return lay
		}
	}
	lay.overlay = true
	lay.split_x = -1
	lay.pane_x = 0
	lay.pane_w = width
	return lay
}

@(private)
app_view_lang_from_path :: proc(path: string) -> string {
	ext := strings.trim_left(filepath.ext(path), ".")
	if len(ext) == 0 {
		return "text"
	}
	return strings.to_lower(ext, context.temp_allocator)
}

@(private)
app_view_line_count :: proc(body: string) -> int {
	if len(body) == 0 {
		return 1
	}
	n := 1
	for r in body {
		if r == '\n' {
			n += 1
		}
	}
	return n
}

app_view_scroll_by :: proc(a: ^App, delta: int, pane_h: int) {
	if !a.view_open || delta == 0 {
		return
	}
	body_h := max(1, pane_h - 3)
	total := app_view_line_count(a.view_body)
	max_scroll := max(0, total - body_h)
	a.view_scroll = clamp(a.view_scroll + delta, 0, max_scroll)
	app_mark_dirty(a)
}

