// SPDX-License-Identifier: 0BSD
/*
Setup wizard keyboard input.
*/

package app

import "core:strings"
import "core:unicode/utf8"
import "nullray:ui"

app_setup_on_event :: proc(a: ^App, ev: ui.Event) -> bool {
	if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
		return true
	}
	if ev.kind == .Esc {
		setup_prev_step(a)
		return false
	}
	if ev.kind == .Tab || ev.kind == .Enter {
		if a.setup_step == .Model {
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
				setup_apply_model_reasoning(a, m)
			}
		}
		setup_next_step(a)
		return false
	}

	#partial switch a.setup_step {
	case .Provider:
		#partial switch ev.kind {
		case .Up, .Mouse_Wheel_Up:
			setup_provider_move(a, -1)
			app_mark_dirty(a)
		case .Down, .Mouse_Wheel_Down:
			setup_provider_move(a, 1)
			app_mark_dirty(a)
		}
	case .Connection:
		#partial switch ev.kind {
		case .Up:
			a.setup_field = 0
			app_mark_dirty(a)
		case .Down:
			if p := setup_selected_provider(a); p != nil && setup_provider_needs_key(p.id) {
				a.setup_field = 1
			}
			app_mark_dirty(a)
		case .Backspace:
			setup_edit_backspace(a)
		case .Rune:
			if ev.ch >= 0x20 {
				setup_edit_insert(a, ev.ch)
			}
		}
	case .Model:
		#partial switch ev.kind {
		case .Up, .Mouse_Wheel_Up:
			a.setup_model_sel = max(0, a.setup_model_sel - 1)
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
			}
			app_mark_dirty(a)
		case .Down, .Mouse_Wheel_Down:
			max_i := max(0, setup_filtered_model_count(a) - 1)
			a.setup_model_sel = min(max_i, a.setup_model_sel + 1)
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
			}
			app_mark_dirty(a)
		case .Backspace:
			setup_filter_backspace(a)
			if len(a.setup_models) == 0 {
				setup_model_backspace(a)
			}
			a.setup_model_sel = 0
			app_mark_dirty(a)
		case .Rune:
			if ev.ch >= 0x20 {
				setup_filter_insert(a, ev.ch)
				a.setup_model_sel = 0
				app_mark_dirty(a)
			}
		}
	case .Reasoning:
		#partial switch ev.kind {
		case .Rune:
			if ev.ch == ' ' {
				p := setup_selected_provider(a)
				if p != nil {
					if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok && m.reasoning_mandatory {
						a.setup_thinking_on = true
					} else {
						a.setup_thinking_on = !a.setup_thinking_on
					}
				}
				if !a.setup_thinking_on {
					delete(a.setup_effort)
					a.setup_effort = strings.clone("none")
				} else if a.setup_effort == "none" || len(a.setup_effort) == 0 {
					delete(a.setup_effort)
					a.setup_effort = strings.clone("low")
				}
				app_mark_dirty(a)
			}
		case .Left:
			setup_effort_nudge(a, -1)
		case .Right:
			setup_effort_nudge(a, 1)
		}
	case .Confirm:
	}
	return false
}

@(private)
setup_edit_target :: proc(a: ^App) -> ^string {
	if a.setup_field == 1 {
		return &a.setup_key
	}
	return &a.setup_base
}

@(private)
setup_edit_backspace :: proc(a: ^App) {
	target := setup_edit_target(a)
	if len(target^) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(target^)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(target^[:len(target^) - sz])
	delete(target^)
	target^ = n
	app_mark_dirty(a)
}

@(private)
setup_edit_insert :: proc(a: ^App, ch: rune) {
	target := setup_edit_target(a)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, target^)
	strings.write_rune(&b, ch)
	nstr := strings.clone(strings.to_string(b))
	delete(target^)
	target^ = nstr
	app_mark_dirty(a)
}

@(private)
setup_filter_backspace :: proc(a: ^App) {
	if len(a.setup_filter) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(a.setup_filter)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(a.setup_filter[:len(a.setup_filter) - sz])
	delete(a.setup_filter)
	a.setup_filter = n
}

@(private)
setup_model_backspace :: proc(a: ^App) {
	if len(a.setup_model) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(a.setup_model)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(a.setup_model[:len(a.setup_model) - sz])
	delete(a.setup_model)
	a.setup_model = n
}

@(private)
setup_filter_insert :: proc(a: ^App, ch: rune) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, a.setup_filter)
	strings.write_rune(&b, ch)
	nstr := strings.clone(strings.to_string(b))
	delete(a.setup_filter)
	a.setup_filter = nstr
	if len(a.setup_models) == 0 {
		b2: strings.Builder
		strings.builder_init(&b2, context.temp_allocator)
		strings.write_string(&b2, a.setup_model)
		strings.write_rune(&b2, ch)
		mstr := strings.clone(strings.to_string(b2))
		delete(a.setup_model)
		a.setup_model = mstr
	}
}

@(private)
setup_effort_nudge :: proc(a: ^App, delta: int) {
	if !a.setup_thinking_on {
		return
	}
	effs := setup_reason_efforts(a)
	idx := 0
	for e, i in effs {
		if e == a.setup_effort {
			idx = i
			break
		}
	}
	idx = clamp(idx + delta, 0, len(effs) - 1)
	delete(a.setup_effort)
	a.setup_effort = strings.clone(effs[idx])
	app_mark_dirty(a)
}
