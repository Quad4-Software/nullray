// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ask

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

@(test)
test_view_parse_basic_form :: proc(t: ^testing.T) {
	raw := `{
  "title": "Ship checklist",
  "body": "Confirm release notes",
  "fields": [
    {"id": "version", "type": "text", "label": "Version", "required": true, "default": "0.8.0"},
    {"id": "notes", "type": "textarea", "label": "Notes"},
    {"id": "dry_run", "type": "checkbox", "label": "Dry run", "default": "true"},
    {"id": "channel", "type": "select", "label": "Channel", "options": ["stable", "beta"], "default": "beta"}
  ],
  "actions": [
    {"id": "ship", "label": "Ship", "type": "submit", "primary": true},
    {"id": "cancel", "label": "Cancel", "type": "cancel"}
  ]
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect_value(t, def.title, "Ship checklist")
	testing.expect_value(t, len(def.fields), 4)
	testing.expect_value(t, def.fields[0].kind, Field_Kind.Text)
	testing.expect(t, def.fields[0].required)
	testing.expect_value(t, def.fields[0].value, "0.8.0")
	testing.expect_value(t, def.fields[2].kind, Field_Kind.Checkbox)
	testing.expect(t, def.fields[2].checked)
	testing.expect_value(t, def.fields[3].kind, Field_Kind.Select)
	testing.expect_value(t, len(def.fields[3].options), 2)
	testing.expect_value(t, def.fields[3].sel, 1)
	testing.expect_value(t, len(def.actions), 2)
	testing.expect(t, def.actions[0].primary)
}

@(test)
test_view_parse_rejects_bad_select :: proc(t: ^testing.T) {
	raw := `{"title":"x","fields":[{"id":"a","type":"select","label":"A"}]}`
	def, err := view_parse(raw, context.allocator)
	testing.expect(t, len(err) > 0)
	view_def_destroy(&def)
	delete(err)
}

@(test)
test_view_parse_unknown_type :: proc(t: ^testing.T) {
	raw := `{"fields":[{"id":"a","type":"laser-beam","label":"Nope"}]}`
	def, err := view_parse(raw, context.allocator)
	testing.expect(t, len(err) > 0)
	view_def_destroy(&def)
	delete(err)
}

@(test)
test_view_validate_required_and_number :: proc(t: ^testing.T) {
	raw := `{
  "fields": [
    {"id": "name", "type": "text", "label": "Name", "required": true},
    {"id": "n", "type": "number", "label": "N", "min": 1, "max": 10, "default": "3"}
  ]
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	// empty required
	delete(def.fields[0].value)
	def.fields[0].value = strings.clone("")
	msg := view_validate(&def, context.allocator)
	testing.expect(t, strings.contains(msg, "required"))
	delete(msg)
	delete(def.fields[0].value)
	def.fields[0].value = strings.clone("ok")
	delete(def.fields[1].value)
	def.fields[1].value = strings.clone("99")
	msg2 := view_validate(&def, context.allocator)
	testing.expect(t, strings.contains(msg2, "<=") || strings.contains(msg2, "must"))
	delete(msg2)
	delete(def.fields[1].value)
	def.fields[1].value = strings.clone("5")
	msg3 := view_validate(&def, context.allocator)
	testing.expect_value(t, msg3, "")
}

@(test)
test_view_result_json_shape :: proc(t: ^testing.T) {
	raw := `{
  "fields": [
    {"id": "city", "type": "text", "default": "Oslo"},
    {"id": "units", "type": "radio", "options": ["C", "F"], "default": "C"},
    {"id": "alerts", "type": "checkbox", "default": "true"}
  ]
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	out := view_result_json(&def, "submit", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"action":"submit"`))
	testing.expect(t, strings.contains(out, `"city":"Oslo"`))
	testing.expect(t, strings.contains(out, `"units":"C"`))
	testing.expect(t, strings.contains(out, `"alerts":true`))
}

@(test)
test_view_caps_field_count :: proc(t: ^testing.T) {
	// Manually oversized list is rejected only by cap, not by invalid JSON.
	// Build 20 valid fields inline so the cap is exercised.
	raw := `{"fields":[
{"id":"f0","type":"text","label":"F0"},{"id":"f1","type":"text","label":"F1"},
{"id":"f2","type":"text","label":"F2"},{"id":"f3","type":"text","label":"F3"},
{"id":"f4","type":"text","label":"F4"},{"id":"f5","type":"text","label":"F5"},
{"id":"f6","type":"text","label":"F6"},{"id":"f7","type":"text","label":"F7"},
{"id":"f8","type":"text","label":"F8"},{"id":"f9","type":"text","label":"F9"},
{"id":"f10","type":"text","label":"F10"},{"id":"f11","type":"text","label":"F11"},
{"id":"f12","type":"text","label":"F12"},{"id":"f13","type":"text","label":"F13"},
{"id":"f14","type":"text","label":"F14"},{"id":"f15","type":"text","label":"F15"},
{"id":"f16","type":"text","label":"F16"},{"id":"f17","type":"text","label":"F17"},
{"id":"f18","type":"text","label":"F18"},{"id":"f19","type":"text","label":"F19"}
]}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect(t, len(def.fields) <= VIEW_MAX_FIELDS)
	testing.expect_value(t, len(def.fields), VIEW_MAX_FIELDS)
}

@(test)
test_view_request_fulfill_roundtrip :: proc(t: ^testing.T) {
	set_ui_enabled(true)
	defer set_ui_enabled(false)
	r := new(T_Result)
	defer free(r)
	schema := `{"title":"T","fields":[{"id":"x","type":"text","default":"hi"}]}`
	th := thread.create_and_start_with_data(r, proc(data: rawptr) {
		rr := cast(^T_Result)data
		ans, ok, canc := request_ex(.View, "T", nil, false, `{"title":"T","fields":[{"id":"x","type":"text","default":"hi"}]}`, 30)
		t_store_answer(rr, ans, ok, canc)
	})
	testing.expect(t, th != nil)
	testing.expect(t, wait_challenge())
	active, id, kind, prompt, options, free_form, view_json := challenge_pending_ex()
	defer delete(prompt)
	defer delete(options)
	defer delete(view_json)
	testing.expect(t, active)
	testing.expect(t, kind == .View)
	testing.expect(t, strings.contains(view_json, "fields"))
	_ = free_form
	_ = schema
	payload := `{"action":"submit","values":{"x":"hi"}}`
	testing.expect(t, fulfill(id, payload))
	thread.join(th)
	thread.destroy(th)
	testing.expect(t, r.ok)
	got := string(r.answer[:r.answer_len])
	testing.expect(t, strings.contains(got, "submit"))
}

@(test)
test_view_default_actions_when_missing :: proc(t: ^testing.T) {
	def, err := view_parse(`{"title":"Info","body":"Hello only"}`, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect(t, len(def.actions) >= 1)
	found_submit := false
	for a in def.actions {
		if a.kind == .Submit || a.kind == .Secondary {
			found_submit = true
		}
	}
	testing.expect(t, found_submit)
}

@(test)
test_view_field_persist_omit_and_redact :: proc(t: ^testing.T) {
	raw := `{
  "fields": [
    {"id": "pub", "type": "text", "default": "visible"},
    {"id": "hid", "type": "text", "default": "nope", "persist": "omit"},
    {"id": "scr", "type": "text", "default": "x", "persist": "redact"},
    {"id": "tok", "type": "text", "default": "s3cret", "persist": "vault", "bind_env": true, "env_name": "DEMO_TOKEN"}
  ]
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	out := view_result_json(&def, "ok", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"pub":"visible"`))
	testing.expect(t, !strings.contains(out, "nope"))
	testing.expect(t, !strings.contains(out, `"hid"`))
	testing.expect(t, strings.contains(out, `"scr":"[redacted]"`))
	testing.expect(t, strings.contains(out, `"tok":"[redacted]"`))
	testing.expect(t, !strings.contains(out, "s3cret"))
	testing.expect(t, secret_has("view.tok") || secret_has("DEMO_TOKEN"))
	_ = secret_forget("view.tok")
	_ = secret_forget("DEMO_TOKEN")
}

@(test)
test_view_password_vaulted_not_in_result :: proc(t: ^testing.T) {
	raw := `{"fields":[{"id":"token","type":"password","default":"super-secret-value"},{"id":"name","type":"text","default":"dev"}]}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	out := view_result_json(&def, "submit", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"token":"[redacted]"`))
	testing.expect(t, !strings.contains(out, "super-secret-value"))
	testing.expect(t, strings.contains(out, `"name":"dev"`))
	testing.expect(t, secret_has("view.token"))
	v := secret_get("view.token")
	testing.expect_value(t, v, "super-secret-value")
	delete(v)
	_ = secret_forget("view.token")
}

@(test)
test_view_modal_size_and_colors :: proc(t: ^testing.T) {
	raw := `{
  "title": "Big",
  "width": 100,
  "height": 40,
  "fg": "#eeeeee",
  "bg": "#111111",
  "accent": "cyan",
  "emoji": true,
  "body": "hello"
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect_value(t, def.width, 100)
	testing.expect_value(t, def.height, 40)
	testing.expect_value(t, def.fg, "#eeeeee")
	testing.expect_value(t, def.accent, "cyan")
	testing.expect(t, def.emoji)
}

@(test)
test_view_width_clamp :: proc(t: ^testing.T) {
	raw := `{"title":"X","width":9999,"height":-3}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect_value(t, def.width, 200)
	testing.expect_value(t, def.height, 0)
}

@(test)
test_view_panel_placement_and_script_action :: proc(t: ^testing.T) {
	raw := `{
  "title": "Dash",
  "placement": "panel",
  "image": "/tmp/x.png",
  "fields": [
    {"id": "n", "type": "number", "label": "N", "default": "1"},
    {"id": "pic", "type": "image", "label": "Pic", "src": "/tmp/y.png"}
  ],
  "actions": [
    {"id": "refresh", "type": "script", "label": "Refresh", "script": "echo {\"n\":\"2\"}"},
    {"id": "ok", "type": "submit", "label": "OK"}
  ]
}`
	def, err := view_parse(raw, context.allocator)
	testing.expect_value(t, err, "")
	defer view_def_destroy(&def)
	testing.expect_value(t, def.placement, View_Placement.Panel)
	testing.expect_value(t, def.image, "/tmp/x.png")
	testing.expect_value(t, def.fields[1].kind, Field_Kind.Image)
	testing.expect_value(t, def.fields[1].src, "/tmp/y.png")
	testing.expect_value(t, def.actions[0].kind, Action_Kind.Script)
	testing.expect(t, strings.contains(def.actions[0].script, "echo"))
}

@(test)
test_path_looks_like_image_helper :: proc(t: ^testing.T) {
	// keep package ask free of ui deps: trivial path suffix checks live here too
	testing.expect(t, strings.has_suffix(strings.to_lower("/a/B.PNG", context.temp_allocator), ".png"))
}
