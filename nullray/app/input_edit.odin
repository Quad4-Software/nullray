// SPDX-License-Identifier: 0BSD
/*
Line editing, insertion, and transcript scroll helpers.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:constants"
import "nullray:ui"

@(private)
app_handle_line_edit :: proc(a: ^App, ev: ui.Event) -> bool {
	switch a.keys_preset {
	case .Default:
		return false
	case .Neovim:
		#partial switch ev.kind {
		case .Ctrl_W:
			app_kill_word_back(a)
			return true
		case .Ctrl_U:
			app_kill_to_start(a)
			return true
		}
	case .Emacs:
		#partial switch ev.kind {
		case .Ctrl_A:
			a.cursor = 0
			app_mark_dirty(a)
			return true
		case .Ctrl_E:
			a.cursor = len(strings.to_string(a.input))
			app_mark_dirty(a)
			return true
		case .Ctrl_B:
			text := strings.to_string(a.input)
			a.cursor = ui.cursor_prev_rune(text, a.cursor)
			app_mark_dirty(a)
			return true
		case .Ctrl_F:
			text := strings.to_string(a.input)
			a.cursor = ui.cursor_next_rune(text, a.cursor)
			app_mark_dirty(a)
			return true
		case .Ctrl_K:
			app_kill_to_end(a)
			return true
		case .Ctrl_W:
			app_kill_word_back(a)
			return true
		case .Ctrl_D:
			app_delete_forward(a)
			return true
		case .Ctrl_U:
			app_kill_to_start(a)
			return true
		}
	}
	return false
}

@(private)
app_kill_word_back :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor <= 0 || len(text) == 0 {
		return
	}
	i := a.cursor
	for i > 0 {
		prev := ui.cursor_prev_rune(text, i)
		r, _ := utf8.decode_rune_in_string(text[prev:i])
		if r != ' ' {
			break
		}
		i = prev
	}
	for i > 0 {
		prev := ui.cursor_prev_rune(text, i)
		r, _ := utf8.decode_rune_in_string(text[prev:i])
		if r == ' ' {
			break
		}
		i = prev
	}
	left := text[:i]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, right)
	a.cursor = i
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_kill_to_start :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor <= 0 {
		return
	}
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, right)
	a.cursor = 0
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_kill_to_end :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor >= len(text) {
		return
	}
	left := text[:a.cursor]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_delete_forward :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor >= len(text) {
		return
	}
	end := ui.cursor_next_rune(text, a.cursor)
	left := text[:a.cursor]
	right := text[end:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, right)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_text :: proc(a: ^App, s: string) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	room := constants.MAX_INPUT_CHARS - len(text)
	if room <= 0 {
		app_toast_warn(a, "input full")
		return
	}
	chunk := s
	if len(chunk) > room {
		chunk = ui.truncate_utf8_bytes(s, room)
		app_toast_warn(a, fmt.tprintf("paste truncated to %d chars", len(chunk)))
	}
	if len(chunk) == 0 {
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, chunk)
	strings.write_string(&a.input, right)
	a.cursor += len(chunk)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_rune :: proc(a: ^App, ch: rune) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	buf, n := utf8.encode_rune(ch)
	if n <= 0 {
		return
	}
	if len(text) + n > constants.MAX_INPUT_CHARS {
		app_toast_warn(a, "input full")
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, string(buf[:n]))
	strings.write_string(&a.input, right)
	a.cursor = len(strings.to_string(a.input)) - len(right)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_scroll_by :: proc(a: ^App, delta: int) {
	if delta == 0 {
		return
	}
	a.follow = false
	a.scroll = max(0, a.scroll + delta)
	if a.scroll == 0 {
		a.follow = true
	}
	app_mark_dirty(a)
}

@(private)
app_scroll_to_top :: proc(a: ^App) {
	a.follow = false
	a.scroll = 1_000_000
	app_mark_dirty(a)
}

@(private)
app_follow_bottom :: proc(a: ^App) {
	a.follow = true
	a.scroll = 0
	app_mark_dirty(a)
}
