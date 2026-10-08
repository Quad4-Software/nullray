// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:ask"
import "nullray:ui"

@(test)
test_view_form_modal_draws :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	raw := `{
  "title": "Weather",
  "body": "Pick a city",
  "fields": [
    {"id": "city", "type": "text", "label": "City", "default": "Oslo", "required": true},
    {"id": "units", "type": "select", "label": "Units", "options": ["C", "F"], "default": "C"},
    {"id": "alerts", "type": "checkbox", "label": "Alerts", "default": "true"}
  ]
}`
	def, err := ask.view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	a.view_form = def
	a.view_form_active = true
	a.ask_active = true
	a.ask_id = 1
	a.ask_kind = .View

	buf := ui.buffer_create(80, 24)
	defer ui.buffer_destroy(&buf)
	app_draw_view_form_modal(&buf, &a)

	found_title := false
	found_city := false
	for y in 0 ..< buf.height {
		row := row_text(&buf, y)
		if strings.contains(row, "Weather") {
			found_title = true
		}
		if strings.contains(row, "City") {
			found_city = true
		}
	}
	testing.expect(t, found_title)
	testing.expect(t, found_city)

	msg := ask.view_validate(&a.view_form, context.allocator)
	testing.expect_value(t, msg, "")
	out := ask.view_result_json(&a.view_form, "submit", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "Oslo"))
	testing.expect(t, strings.contains(out, "alerts"))
}

@(test)
test_view_form_tab_and_checkbox :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	raw := `{"title":"T","fields":[
{"id":"a","type":"text","label":"A","default":"x"},
{"id":"b","type":"checkbox","label":"B","default":"false"}
]}`
	def, err := ask.view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	a.view_form = def
	a.view_form_active = true
	a.ask_active = true
	a.ask_id = 42
	a.ask_kind = .View
	a.view_form_focus = 0

	_ = app_view_form_on_event(&a, ui.Event{kind = .Tab})
	testing.expect_value(t, a.view_form_focus, 1)
	_ = app_view_form_on_event(&a, ui.Event{kind = .Rune, ch = ' '})
	testing.expect(t, a.view_form.fields[1].checked)

	delete(a.view_form.fields[0].value)
	a.view_form.fields[0].value = strings.clone("")
	a.view_form.fields[0].required = true
	// Focus the submit action.
	for i in 0 ..< len(a.view_form.actions) {
		if a.view_form.actions[i].kind == .Submit {
			idx := 0
			for f in a.view_form.fields {
				#partial switch f.kind {
				case .Label, .Markdown, .Separator, .Image:
				case:
					idx += 1
				}
			}
			a.view_form_focus = idx + i
			break
		}
	}
	_ = app_view_form_on_event(&a, ui.Event{kind = .Enter})
	testing.expect(t, a.view_form_active)
	testing.expect(t, len(a.view_form_err) > 0)
}
