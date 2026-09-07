// SPDX-License-Identifier: 0BSD
/*
TUI masked password modal for elevate askpass challenges.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:elevate"
import "nullray:ui"

app_elevate_clear :: proc(a: ^App) {
	a.elevate_active = false
	a.elevate_id = 0
	delete(a.elevate_prompt)
	a.elevate_prompt = {}
	delete(a.elevate_command)
	a.elevate_command = {}
	if len(a.elevate_buf) > 0 {
		elevate.zero_and_delete(a.elevate_buf)
	}
	a.elevate_buf = {}
}

app_elevate_poll :: proc(a: ^App) -> bool {
	active, id, prompt, command := elevate.challenge_pending()
	if !active {
		if a.elevate_active {
			app_elevate_clear(a)
			return true
		}
		return false
	}
	changed := false
	if !a.elevate_active || a.elevate_id != id {
		app_elevate_clear(a)
		a.elevate_active = true
		a.elevate_id = id
		a.elevate_prompt = prompt
		a.elevate_command = command
		a.elevate_buf = {}
		changed = true
	} else {
		delete(prompt)
		delete(command)
	}
	return changed
}

app_elevate_on_event :: proc(a: ^App, ev: ui.Event) -> bool {
	if !a.elevate_active {
		return false
	}
	if ev.kind == .Ctrl_Q {
		return true
	}
	if ev.kind == .Esc || ev.kind == .Ctrl_C {
		_ = elevate.cancel_challenge(a.elevate_id)
		app_elevate_clear(a)
		app_mark_dirty(a)
		return false
	}
	#partial switch ev.kind {
	case .Enter:
		pw := a.elevate_buf
		a.elevate_buf = {}
		_ = elevate.fulfill_password(a.elevate_id, pw)
		elevate.zero_and_delete(pw)
		app_elevate_clear(a)
		app_mark_dirty(a)
	case .Backspace:
		if len(a.elevate_buf) > 0 {
			_, size := utf8.decode_last_rune_in_string(a.elevate_buf)
			if size > 0 {
				new_s := strings.clone(a.elevate_buf[:len(a.elevate_buf) - size])
				elevate.zero_and_delete(a.elevate_buf)
				a.elevate_buf = new_s
				app_mark_dirty(a)
			}
		}
	case .Rune:
		if ev.ch >= 0x20 {
			b: strings.Builder
			strings.builder_init(&b)
			strings.write_string(&b, a.elevate_buf)
			strings.write_rune(&b, ev.ch)
			nstr := strings.clone(strings.to_string(b))
			strings.builder_destroy(&b)
			if len(a.elevate_buf) > 0 {
				elevate.zero_and_delete(a.elevate_buf)
			}
			a.elevate_buf = nstr
			app_mark_dirty(a)
		}
	}
	return false
}

app_draw_elevate_modal :: proc(buf: ^ui.Buffer, a: ^App) {
	if !a.elevate_active {
		return
	}
	t := ui.theme()
	w := min(64, max(40, buf.width - 4))
	h := 8
	x := max(0, (buf.width - w) / 2)
	y := max(1, (buf.height - h) / 2)
	ui.draw_box(buf, x, y, w, h, t.accent, t.bg, "Elevated command")
	cmd := a.elevate_command
	max_cmd := max(1, w - 4)
	if ui.string_cols(cmd) > max_cmd {
		// byte truncate for display only
		cut := min(len(cmd), max_cmd - 1)
		cmd = fmt.tprintf("%s…", cmd[:cut])
	}
	ui.buffer_text_clip(buf, x + 2, y + 2, x + w - 2, cmd, t.muted, t.bg)
	prompt := a.elevate_prompt
	if len(prompt) == 0 {
		prompt = "Password:"
	}
	ui.buffer_text_clip(buf, x + 2, y + 4, x + w - 2, prompt, t.fg, t.bg)
	n := utf8.rune_count_in_string(a.elevate_buf)
	mask_n := min(n, max(0, w - 4))
	mask, _ := strings.repeat("*", mask_n, context.temp_allocator)
	ui.buffer_text_clip(buf, x + 2, y + 5, x + w - 2, mask, t.accent, t.bg)
	ui.buffer_text_clip(buf, x + 2, y + 6, x + w - 2, "Enter submit · Esc cancel", t.muted, t.bg)
}
