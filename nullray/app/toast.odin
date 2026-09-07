// SPDX-License-Identifier: 0BSD
/*
Reusable toast notifications for the TUI.
*/

package app

import "core:strings"
import "core:time"
import "nullray:ui"

Toast_Kind :: enum {
	Info,
	Ok,
	Warn,
	Error,
}

Toast :: struct {
	text:    string,
	kind:    Toast_Kind,
	created: time.Tick,
	ttl_ms:  int,
}

TOAST_DEFAULT_MS :: 2800
TOAST_MAX :: 4

app_toast :: proc(a: ^App, text: string, kind: Toast_Kind = .Info, ms: int = TOAST_DEFAULT_MS) {
	if len(strings.trim_space(text)) == 0 {
		return
	}
	for len(a.toasts) >= TOAST_MAX {
		old := a.toasts[0]
		delete(old.text)
		ordered_remove(&a.toasts, 0)
	}
	append(
		&a.toasts,
		Toast{
			text = strings.clone(text),
			kind = kind,
			created = time.tick_now(),
			ttl_ms = max(500, ms),
		},
	)
	app_mark_dirty(a)
}

app_toast_ok :: proc(a: ^App, text: string) {
	app_toast(a, text, .Ok)
}

app_toast_warn :: proc(a: ^App, text: string) {
	app_toast(a, text, .Warn)
}

app_toast_error :: proc(a: ^App, text: string) {
	app_toast(a, text, .Error)
}

app_toasts_expire :: proc(a: ^App) -> bool {
	changed := false
	now := time.tick_now()
	for i := len(a.toasts) - 1; i >= 0; i -= 1 {
		age := time.tick_diff(a.toasts[i].created, now)
		if age >= time.Duration(a.toasts[i].ttl_ms) * time.Millisecond {
			delete(a.toasts[i].text)
			ordered_remove(&a.toasts, i)
			changed = true
		}
	}
	return changed
}

app_toasts_destroy :: proc(a: ^App) {
	for t in a.toasts {
		delete(t.text)
	}
	delete(a.toasts)
	a.toasts = {}
}

@(private)
toast_colors :: proc(kind: Toast_Kind, t: ui.Theme) -> (fg, bg: ui.Color) {
	switch kind {
	case .Info:
		return t.highlight_fg, t.highlight_bg
	case .Ok:
		return t.bg, t.ok
	case .Warn:
		return t.bg, t.warn
	case .Error:
		return t.highlight_fg, t.error
	}
	return t.fg, t.highlight_bg
}

app_draw_toasts :: proc(buf: ^ui.Buffer, a: ^App) {
	n := len(a.toasts)
	if n == 0 {
		return
	}
	t := ui.theme()
	y := buf.height - 3 - n
	if y < 2 {
		y = 2
	}
	for i in 0 ..< n {
		toast := a.toasts[i]
		fg, bg := toast_colors(toast.kind, t)
		label := toast.text
		w := min(buf.width - 4, ui.string_cols(label) + 4)
		if w < 8 {
			w = min(buf.width - 2, 8)
		}
		x := max(0, buf.width - w - 1)
		row := y + i
		if row >= buf.height - 3 {
			break
		}
		ui.buffer_fill_rect(buf, x, row, w, 1, ' ', fg, bg)
		ui.buffer_text_clip(buf, x + 2, row, x + w - 1, label, fg, bg, {.Bold})
	}
}
