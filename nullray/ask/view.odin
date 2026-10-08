// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Declarative custom view forms for the agent. The LLM describes a modal with
title, body, typed fields, and actions. The TUI renders it, validates input,
and returns a structured JSON answer. Caps and type guards keep bad schemas
from hanging or crashing the UI.
*/

package ask

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

VIEW_MAX_FIELDS :: 16
VIEW_MAX_OPTIONS :: 12
VIEW_MAX_ACTIONS :: 6
VIEW_MAX_TITLE :: 80
VIEW_MAX_BODY :: 4000
VIEW_MAX_LABEL :: 120
VIEW_MAX_PLACEHOLDER :: 80
VIEW_MAX_DEFAULT :: 500
VIEW_MAX_ID :: 40
VIEW_MAX_VALUE :: 2000
VIEW_MAX_IMAGE_PATH :: 512
VIEW_MAX_SCRIPT :: 240
VIEW_DEFAULT_TIMEOUT_SEC :: 600
VIEW_SCRIPT_TIMEOUT_MS :: 8_000
VIEW_SCRIPT_MAX_OUTPUT :: 8_000

Field_Kind :: enum {
	Text,
	Textarea,
	Number,
	Checkbox,
	Select,
	Radio,
	Password,
	Label,
	Markdown,
	Separator,
	Image,
}

Action_Kind :: enum {
	Submit,
	Cancel,
	Secondary,
	Script, // runs a workspace-relative command and refreshes field values
}

View_Placement :: enum {
	Modal,
	Panel,
}

// What happens to a field value after submit for model + disk.
Field_Persist :: enum {
	Normal,  // plain value in JSON + transcript (subject to global scrub)
	Redact,  // always [redacted] in JSON; not vaulted
	Vault,   // secret_put under view.<id>, JSON [redacted]
	Omit,    // drop from returned JSON entirely (never send to model)
}

View_Field :: struct {
	id:          string,
	kind:        Field_Kind,
	label:       string,
	placeholder: string,
	required:    bool,
	options:     [dynamic]string,
	default:     string,
	min:         f64,
	max:         f64,
	has_min:     bool,
	has_max:     bool,
	pattern:     string, // literal substring guard only (not full regex)
	value:       string, // live edit buffer (owned when in App)
	checked:     bool,
	sel:         int, // select/radio index
	src:         string, // image path or URL label
	cols:        int,
	rows:        int,
	persist:     Field_Persist,
	bind_env:    bool, // after vault, also secret_bind_env(view.id or env name)
	env_name:    string, // optional env name when bind_env
}

View_Action :: struct {
	id:      string,
	label:   string,
	kind:    Action_Kind,
	primary: bool,
	script:  string, // workspace-relative command for Script actions
}

View_Def :: struct {
	title:     string,
	body:      string,
	fields:    [dynamic]View_Field,
	actions:   [dynamic]View_Action,
	placement: View_Placement,
	image:     string, // optional banner image path for the whole view
	// Modal geometry (0 = auto). Agent can size the box.
	width:     int,
	height:    int,
	// Optional per-view colors (hex/name). Empty = inherit TUI theme.
	fg:        string,
	bg:        string,
	accent:    string,
	border:    string,
	// When true, body/labels may contain emoji; default true.
	emoji:     bool,
	style:     string, // "plain"|"ansi"|"rich" (hint only; always truecolor when available)
}

view_field_destroy :: proc(f: ^View_Field) {
	if f == nil {
		return
	}
	delete(f.id)
	delete(f.label)
	delete(f.placeholder)
	delete(f.default)
	delete(f.pattern)
	delete(f.value)
	delete(f.src)
	delete(f.env_name)
	for o in f.options {
		delete(o)
	}
	delete(f.options)
	f^ = {}
}

view_def_destroy :: proc(v: ^View_Def) {
	if v == nil {
		return
	}
	delete(v.title)
	delete(v.body)
	delete(v.image)
	delete(v.fg)
	delete(v.bg)
	delete(v.accent)
	delete(v.border)
	delete(v.style)
	for &f in v.fields {
		view_field_destroy(&f)
	}
	delete(v.fields)
	for a in v.actions {
		delete(a.id)
		delete(a.label)
		delete(a.script)
	}
	delete(v.actions)
	v^ = {}
}

view_field_kind_parse :: proc(s: string) -> (Field_Kind, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "text", "input", "string":
		return .Text, true
	case "textarea", "multiline", "note":
		return .Textarea, true
	case "number", "int", "float", "num":
		return .Number, true
	case "checkbox", "check", "bool", "toggle":
		return .Checkbox, true
	case "select", "dropdown", "combo":
		return .Select, true
	case "radio", "choice":
		return .Radio, true
	case "password", "secret", "masked":
		return .Password, true
	case "label", "static":
		return .Label, true
	case "markdown", "md", "html":
		// markdown is rendered as plain wrap for now
		return .Markdown, true
	case "separator", "hr", "divider":
		return .Separator, true
	case "image", "img", "picture":
		return .Image, true
	}
	return .Text, false
}

view_placement_parse :: proc(s: string) -> View_Placement {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "panel", "side", "pane", "sidebar", "dock":
		return .Panel
	}
	return .Modal
}

view_sanitize_id :: proc(raw: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in raw {
		if unicode.is_letter(r) || unicode.is_digit(r) || r == '_' || r == '-' {
			strings.write_rune(&b, r)
		}
	}
	out := strings.to_string(b)
	if len(out) > VIEW_MAX_ID {
		trimmed := strings.clone(out[:VIEW_MAX_ID], allocator)
		delete(out)
		return trimmed
	}
	if len(out) == 0 {
		delete(out)
		return strings.clone("field", allocator)
	}
	return out
}

view_clip :: proc(s: string, max_n: int, allocator := context.allocator) -> string {
	if max_n <= 0 || len(s) <= max_n {
		return strings.clone(s, allocator)
	}
	return strings.clone(s[:max_n], allocator)
}

/*
Parse a view definition from JSON. Accepts either a full object or a string
containing JSON. On failure returns a human-readable err for the model.
*/
view_parse :: proc(raw: string, allocator := context.allocator) -> (def: View_Def, err: string) {
	src := strings.trim_space(raw)
	if len(src) == 0 {
		return {}, strings.clone("view schema is empty", allocator)
	}
	// Allow a bare JSON object or a JSON string holding one.
	doc, perr := json.parse_string(src, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return {}, strings.clone("view schema is not valid JSON", allocator)
	}
	if s, sok := doc.(json.String); sok {
		inner := string(s)
		doc2, perr2 := json.parse_string(inner, .JSON, allocator = context.temp_allocator)
		if perr2 != .None {
			return {}, strings.clone("view schema string is not valid JSON", allocator)
		}
		doc = doc2
	}
	obj, ook := doc.(json.Object)
	if !ook {
		return {}, strings.clone("view schema root must be an object", allocator)
	}

	title := json_string_field(obj, "title")
	if len(title) == 0 {
		title = "View"
	}
	body := json_string_field(obj, "body")
	if len(body) == 0 {
		body = json_string_field(obj, "text")
	}
	if len(body) == 0 {
		body = json_string_field(obj, "markdown")
	}

	def.title = view_clip(title, VIEW_MAX_TITLE, allocator)
	def.body = view_clip(body, VIEW_MAX_BODY, allocator)
	place_s := json_string_field(obj, "placement")
	if len(place_s) == 0 {
		place_s = json_string_field(obj, "place")
	}
	if len(place_s) == 0 {
		place_s = json_string_field(obj, "target")
	}
	def.placement = view_placement_parse(place_s)
	if json_bool_field(obj, "panel") || json_bool_field(obj, "side") {
		def.placement = .Panel
	}
	img := json_string_field(obj, "image")
	if len(img) == 0 {
		img = json_string_field(obj, "banner")
	}
	def.image = view_clip(img, VIEW_MAX_IMAGE_PATH, allocator)
	def.emoji = true
	if _, has := obj["emoji"]; has {
		def.emoji = json_bool_field(obj, "emoji")
	}
	def.fg = view_clip(json_string_field(obj, "fg"), 32, allocator)
	def.bg = view_clip(json_string_field(obj, "bg"), 32, allocator)
	def.accent = view_clip(json_string_field(obj, "accent"), 32, allocator)
	def.border = view_clip(json_string_field(obj, "border"), 32, allocator)
	def.style = view_clip(json_string_field(obj, "style"), 16, allocator)
	if wv, has := obj["width"]; has {
		if n, nok := json_number_value(wv); nok {
			def.width = int(n)
		}
	}
	if hv, has := obj["height"]; has {
		if n, nok := json_number_value(hv); nok {
			def.height = int(n)
		}
	}
	// Clamp geometry into safe bounds (absolute max, actual draw clamps to term).
	if def.width < 0 {
		def.width = 0
	}
	if def.width > 200 {
		def.width = 200
	}
	if def.height < 0 {
		def.height = 0
	}
	if def.height > 80 {
		def.height = 80
	}
	def.fields = make([dynamic]View_Field, 0, 8, allocator)
	def.actions = make([dynamic]View_Action, 0, 4, allocator)

	seen_ids := make(map[string]bool, context.temp_allocator)

	if fv, has := obj["fields"]; has {
		arr, aok := fv.(json.Array)
		if !aok {
			view_def_destroy(&def)
			return {}, strings.clone("fields must be an array", allocator)
		}
		for item, i in arr {
			if len(def.fields) >= VIEW_MAX_FIELDS {
				break
			}
			fobj, fok := item.(json.Object)
			if !fok {
				view_def_destroy(&def)
				return {}, fmt.aprintf("fields[%d] must be an object", i, allocator = allocator)
			}
			f, ferr := view_parse_field(fobj, i, allocator)
			if ferr != "" {
				view_def_destroy(&def)
				view_field_destroy(&f)
				return {}, ferr
			}
			if seen_ids[f.id] {
				// Dedup by suffix so the form still works.
				base := f.id
				delete(f.id)
				f.id = fmt.aprintf("%s_%d", base, i + 1, allocator = allocator)
			}
			seen_ids[f.id] = true
			// Seed live value from default.
			if f.kind == .Checkbox {
				low := strings.to_lower(strings.trim_space(f.default), context.temp_allocator)
				f.checked = low == "1" || low == "true" || low == "yes" || low == "on"
			} else if f.kind == .Select || f.kind == .Radio {
				f.sel = 0
				if len(f.default) > 0 {
					for o, oi in f.options {
						if o == f.default {
							f.sel = oi
							break
						}
					}
				}
				if len(f.options) > 0 {
					f.value = strings.clone(f.options[f.sel], allocator)
				}
			} else if f.kind == .Image {
				if len(f.src) == 0 {
					f.src = strings.clone(f.default, allocator)
				}
			} else if f.kind != .Separator && f.kind != .Label && f.kind != .Markdown {
				f.value = strings.clone(f.default, allocator)
			}
			append(&def.fields, f)
		}
	}

	if av, has := obj["actions"]; has {
		arr, aok := av.(json.Array)
		if !aok {
			view_def_destroy(&def)
			return {}, strings.clone("actions must be an array", allocator)
		}
		for item, i in arr {
			if len(def.actions) >= VIEW_MAX_ACTIONS {
				break
			}
			aobj, aok2 := item.(json.Object)
			if !aok2 {
				view_def_destroy(&def)
				return {}, fmt.aprintf("actions[%d] must be an object", i, allocator = allocator)
			}
			act, aerr := view_parse_action(aobj, i, allocator)
			if aerr != "" {
				view_def_destroy(&def)
				delete(act.id)
				delete(act.label)
				delete(act.script)
				return {}, aerr
			}
			append(&def.actions, act)
		}
	}

	// Default actions when none provided.
	if len(def.actions) == 0 {
		append(&def.actions, View_Action{
			id = strings.clone("submit", allocator),
			label = strings.clone("Submit", allocator),
			kind = .Submit,
			primary = true,
		})
		append(&def.actions, View_Action{
			id = strings.clone("cancel", allocator),
			label = strings.clone("Cancel", allocator),
			kind = .Cancel,
			primary = false,
		})
	}
	// Ensure at least one submit-like action if only cancel was given.
	has_submit := false
	for a in def.actions {
		if a.kind == .Submit || a.kind == .Secondary {
			has_submit = true
			break
		}
	}
	if !has_submit {
		append(&def.actions, View_Action{
			id = strings.clone("ok", allocator),
			label = strings.clone("OK", allocator),
			kind = .Submit,
			primary = true,
		})
	}

	// Showcase-only forms (labels/markdown, no inputs) still need OK.
	return def, ""
}

@(private)
view_parse_field :: proc(obj: json.Object, idx: int, allocator := context.allocator) -> (f: View_Field, err: string) {
	id_raw := json_string_field(obj, "id")
	if len(id_raw) == 0 {
		id_raw = json_string_field(obj, "name")
	}
	if len(id_raw) == 0 {
		id_raw = fmt.tprintf("field_%d", idx + 1)
	}
	type_raw := json_string_field(obj, "type")
	if len(type_raw) == 0 {
		type_raw = json_string_field(obj, "kind")
	}
	kind, kok := view_field_kind_parse(type_raw)
	if len(type_raw) > 0 && !kok {
		return {}, fmt.aprintf("fields[%d]: unknown type %s", idx, type_raw, allocator = allocator)
	}
	if len(type_raw) == 0 {
		kind = .Text
	}
	f.id = view_sanitize_id(id_raw, allocator)
	f.kind = kind
	f.label = view_clip(json_string_field(obj, "label"), VIEW_MAX_LABEL, allocator)
	if len(f.label) == 0 && kind != .Separator {
		delete(f.label)
		f.label = strings.clone(f.id, allocator)
	}
	f.placeholder = view_clip(json_string_field(obj, "placeholder"), VIEW_MAX_PLACEHOLDER, allocator)
	f.default = view_clip(json_string_field(obj, "default"), VIEW_MAX_DEFAULT, allocator)
	f.pattern = view_clip(json_string_field(obj, "pattern"), VIEW_MAX_PLACEHOLDER, allocator)
	src := json_string_field(obj, "src")
	if len(src) == 0 {
		src = json_string_field(obj, "path")
	}
	if len(src) == 0 {
		src = json_string_field(obj, "url")
	}
	f.src = view_clip(src, VIEW_MAX_IMAGE_PATH, allocator)
	f.persist = .Normal
	if kind == .Password {
		f.persist = .Vault
	}
	ps := json_string_field(obj, "persist")
	if len(ps) == 0 {
		ps = json_string_field(obj, "policy")
	}
	switch strings.to_lower(strings.trim_space(ps), context.temp_allocator) {
	case "redact", "scrub":
		f.persist = .Redact
	case "vault", "secret", "password":
		f.persist = .Vault
	case "omit", "never", "drop", "private":
		f.persist = .Omit
	case "normal", "plain", "send":
		f.persist = .Normal
	}
	if json_bool_field(obj, "vault") || json_bool_field(obj, "secret") {
		f.persist = .Vault
	}
	if json_bool_field(obj, "omit") || json_bool_field(obj, "private") {
		f.persist = .Omit
	}
	f.bind_env = json_bool_field(obj, "bind_env") || json_bool_field(obj, "env")
	f.env_name = view_clip(json_string_field(obj, "env_name"), VIEW_MAX_ID, allocator)
	if cv, has := obj["cols"]; has {
		if n, nok := json_number_value(cv); nok {
			f.cols = int(n)
		}
	}
	if rv, has := obj["rows"]; has {
		if n, nok := json_number_value(rv); nok {
			f.rows = int(n)
		}
	}
	f.required = json_bool_field(obj, "required")
	if mv, has := obj["min"]; has {
		if n, nok := json_number_value(mv); nok {
			f.min = n
			f.has_min = true
		}
	}
	if mv, has := obj["max"]; has {
		if n, nok := json_number_value(mv); nok {
			f.max = n
			f.has_max = true
		}
	}
	f.options = make([dynamic]string, 0, 4, allocator)
	if ov, has := obj["options"]; has {
		arr, aok := ov.(json.Array)
		if !aok {
			return f, fmt.aprintf("fields[%d].options must be an array", idx, allocator = allocator)
		}
		for oitem in arr {
			if len(f.options) >= VIEW_MAX_OPTIONS {
				break
			}
			s := ""
			if os, sok := oitem.(json.String); sok {
				s = string(os)
			} else if oo, ook := oitem.(json.Object); ook {
				s = json_string_field(oo, "label")
				if len(s) == 0 {
					s = json_string_field(oo, "value")
				}
			}
			s = strings.trim_space(s)
			if len(s) == 0 {
				continue
			}
			append(&f.options, view_clip(s, VIEW_MAX_LABEL, allocator))
		}
	}
	if (kind == .Select || kind == .Radio) && len(f.options) == 0 {
		return f, fmt.aprintf("fields[%d] (%s) needs options", idx, f.id, allocator = allocator)
	}
	if kind == .Image && len(f.src) == 0 && len(f.default) == 0 {
		return f, fmt.aprintf("fields[%d] (%s) image needs src or default path", idx, f.id, allocator = allocator)
	}
	return f, ""
}

@(private)
view_parse_action :: proc(obj: json.Object, idx: int, allocator := context.allocator) -> (a: View_Action, err: string) {
	id_raw := json_string_field(obj, "id")
	if len(id_raw) == 0 {
		id_raw = json_string_field(obj, "name")
	}
	label := json_string_field(obj, "label")
	if len(label) == 0 {
		label = id_raw
	}
	if len(label) == 0 {
		label = fmt.tprintf("Action %d", idx + 1)
	}
	kind_s := strings.to_lower(json_string_field(obj, "type"), context.temp_allocator)
	if len(kind_s) == 0 {
		kind_s = strings.to_lower(json_string_field(obj, "kind"), context.temp_allocator)
	}
	a.kind = .Submit
	switch kind_s {
	case "cancel", "close", "dismiss":
		a.kind = .Cancel
	case "secondary", "alt", "other":
		a.kind = .Secondary
	case "script", "run", "exec", "command":
		a.kind = .Script
	case "submit", "ok", "primary", "":
		a.kind = .Submit
	case:
		// Unknown action type: treat as secondary so the form still works.
		a.kind = .Secondary
	}
	if json_bool_field(obj, "cancel") {
		a.kind = .Cancel
	}
	if json_bool_field(obj, "primary") {
		a.primary = true
		if a.kind == .Secondary {
			a.kind = .Submit
		}
	}
	script := json_string_field(obj, "script")
	if len(script) == 0 {
		script = json_string_field(obj, "command")
	}
	if len(script) == 0 {
		script = json_string_field(obj, "run")
	}
	a.script = view_clip(strings.trim_space(script), VIEW_MAX_SCRIPT, allocator)
	if a.kind == .Script && len(a.script) == 0 {
		return a, fmt.aprintf("actions[%d] script requires script/command", idx, allocator = allocator)
	}
	// A submit action with a script field still runs the script first style
	// is available via explicit type=script.
	if len(id_raw) == 0 {
		id_raw = a.kind == .Cancel ? "cancel" : (a.kind == .Script ? "run" : "submit")
	}
	a.id = view_sanitize_id(id_raw, allocator)
	a.label = view_clip(label, VIEW_MAX_LABEL, allocator)
	return a, ""
}

json_string_field :: proc(obj: json.Object, key: string) -> string {
	v, has := obj[key]
	if !has {
		return ""
	}
	if s, ok := v.(json.String); ok {
		return string(s)
	}
	return ""
}

json_bool_field :: proc(obj: json.Object, key: string) -> bool {
	v, has := obj[key]
	if !has {
		return false
	}
	if b, ok := v.(json.Boolean); ok {
		return bool(b)
	}
	if s, ok := v.(json.String); ok {
		low := strings.to_lower(strings.trim_space(string(s)), context.temp_allocator)
		return low == "1" || low == "true" || low == "yes" || low == "on"
	}
	if n, ok := json_number_value(v); ok {
		return n != 0
	}
	return false
}

json_number_value :: proc(v: json.Value) -> (f64, bool) {
	#partial switch t in v {
	case json.Integer:
		return f64(t), true
	case json.Float:
		return f64(t), true
	case json.String:
		n, ok := strconv.parse_f64(strings.trim_space(string(t)))
		return n, ok
	}
	return 0, false
}

/*
Validate live field values. Returns "" on success or a message naming the
first bad field. Does not allocate the message unless there is an error.
*/
view_validate :: proc(def: ^View_Def, allocator := context.allocator) -> string {
	if def == nil {
		return strings.clone("no view", allocator)
	}
	for f in def.fields {
		switch f.kind {
		case .Separator, .Label, .Markdown, .Image:
			continue
		case .Checkbox:
			// always valid
		case .Select, .Radio:
			if f.required && (f.sel < 0 || f.sel >= len(f.options)) {
				return fmt.aprintf("%s: choose an option", f.label, allocator = allocator)
			}
		case .Text, .Textarea, .Password, .Number:
			val := strings.trim_space(f.value)
			if f.required && len(val) == 0 {
				return fmt.aprintf("%s is required", f.label, allocator = allocator)
			}
			if f.kind == .Number && len(val) > 0 {
				n, ok := strconv.parse_f64(val)
				if !ok {
					return fmt.aprintf("%s must be a number", f.label, allocator = allocator)
				}
				if f.has_min && n < f.min {
					return fmt.aprintf("%s must be >= %v", f.label, f.min, allocator = allocator)
				}
				if f.has_max && n > f.max {
					return fmt.aprintf("%s must be <= %v", f.label, f.max, allocator = allocator)
				}
			}
			if len(f.pattern) > 0 && len(val) > 0 && !strings.contains(val, f.pattern) {
				return fmt.aprintf("%s must contain %s", f.label, f.pattern, allocator = allocator)
			}
			if utf8.rune_count_in_string(f.value) > VIEW_MAX_VALUE {
				return fmt.aprintf("%s is too long", f.label, allocator = allocator)
			}
		}
	}
	return ""
}

// Build the JSON payload returned to the model after submit.
// Password fields are vaulted under view.<id> and never leave as plain
// values. The model only sees [redacted] (same marker as outbound scrub).
VIEW_PASSWORD_REDACTED :: "[redacted]"
VIEW_PASSWORD_VAULT_PREFIX :: "view."

view_result_json :: proc(def: ^View_Def, action_id: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"action":`)
	view_write_json_string(&b, action_id)
	strings.write_string(&b, `,"values":{`)
	first := true
	for f in def.fields {
		#partial switch f.kind {
		case .Separator, .Label, .Markdown, .Image:
			continue
		}
		if f.persist == .Omit {
			continue
		}
		if !first {
			strings.write_byte(&b, ',')
		}
		first = false
		view_write_json_string(&b, f.id)
		strings.write_byte(&b, ':')
		// Effective policy: password fields always vault unless omit.
		pol := f.persist
		if f.kind == .Password && pol == .Normal {
			pol = .Vault
		}
		if pol == .Redact {
			view_write_json_string(&b, VIEW_PASSWORD_REDACTED)
			continue
		}
		if pol == .Vault {
			if len(strings.trim_space(f.value)) > 0 && len(f.id) > 0 {
				vault_name := strings.concatenate({VIEW_PASSWORD_VAULT_PREFIX, f.id}, context.temp_allocator)
				secret_put(vault_name, f.value)
				if f.bind_env {
					env_n := f.env_name
					if len(env_n) == 0 {
						env_n = vault_name
					}
					// Also store under env name so bind/export can find it.
					if env_n != vault_name {
						secret_put(env_n, f.value)
					}
					_ = secret_bind_env(env_n)
				}
			}
			view_write_json_string(&b, VIEW_PASSWORD_REDACTED)
			continue
		}
		#partial switch f.kind {
		case .Checkbox:
			strings.write_string(&b, f.checked ? "true" : "false")
		case .Number:
			val := strings.trim_space(f.value)
			if len(val) == 0 {
				strings.write_string(&b, "null")
			} else if _, ok := strconv.parse_f64(val); ok {
				strings.write_string(&b, val)
			} else {
				view_write_json_string(&b, val)
			}
		case .Select, .Radio:
			if f.sel >= 0 && f.sel < len(f.options) {
				view_write_json_string(&b, f.options[f.sel])
			} else {
				view_write_json_string(&b, f.value)
			}
		case:
			view_write_json_string(&b, f.value)
		}
	}
	strings.write_string(&b, `}}`)
	return strings.to_string(b)
}

@(private)
view_write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		switch c {
		case '"', '\\':
			strings.write_byte(b, '\\')
			strings.write_byte(b, c)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if c < 0x20 {
				fmt.sbprintf(b, `\u%04x`, c)
			} else {
				strings.write_byte(b, c)
			}
		}
	}
	strings.write_byte(b, '"')
}

// Clone a view def deeply under allocator (for TUI ownership).
view_def_clone :: proc(src: View_Def, allocator := context.allocator) -> View_Def {
	out: View_Def
	out.title = strings.clone(src.title, allocator)
	out.body = strings.clone(src.body, allocator)
	out.image = strings.clone(src.image, allocator)
	out.placement = src.placement
	out.width = src.width
	out.height = src.height
	out.fg = strings.clone(src.fg, allocator)
	out.bg = strings.clone(src.bg, allocator)
	out.accent = strings.clone(src.accent, allocator)
	out.border = strings.clone(src.border, allocator)
	out.emoji = src.emoji
	out.style = strings.clone(src.style, allocator)
	out.fields = make([dynamic]View_Field, 0, len(src.fields), allocator)
	for f in src.fields {
		nf: View_Field
		nf.id = strings.clone(f.id, allocator)
		nf.kind = f.kind
		nf.label = strings.clone(f.label, allocator)
		nf.placeholder = strings.clone(f.placeholder, allocator)
		nf.required = f.required
		nf.default = strings.clone(f.default, allocator)
		nf.min = f.min
		nf.max = f.max
		nf.has_min = f.has_min
		nf.has_max = f.has_max
		nf.pattern = strings.clone(f.pattern, allocator)
		nf.value = strings.clone(f.value, allocator)
		nf.checked = f.checked
		nf.sel = f.sel
		nf.src = strings.clone(f.src, allocator)
		nf.cols = f.cols
		nf.rows = f.rows
		nf.persist = f.persist
		nf.bind_env = f.bind_env
		nf.env_name = strings.clone(f.env_name, allocator)
		nf.options = make([dynamic]string, 0, len(f.options), allocator)
		for o in f.options {
			append(&nf.options, strings.clone(o, allocator))
		}
		append(&out.fields, nf)
	}
	out.actions = make([dynamic]View_Action, 0, len(src.actions), allocator)
	for a in src.actions {
		append(&out.actions, View_Action{
			id = strings.clone(a.id, allocator),
			label = strings.clone(a.label, allocator),
			kind = a.kind,
			primary = a.primary,
			script = strings.clone(a.script, allocator),
		})
	}
	return out
}

view_focusable_count :: proc(def: ^View_Def) -> int {
	if def == nil {
		return 0
	}
	n := 0
	for f in def.fields {
		#partial switch f.kind {
		case .Label, .Markdown, .Separator, .Image:
		case:
			n += 1
		}
	}
	// Actions are also focusable at the end.
	n += len(def.actions)
	return n
}

// Map a focus index (0..) to a field index or -1 for action, with action_i set.
view_focus_resolve :: proc(def: ^View_Def, focus: int) -> (field_i: int, action_i: int, is_action: bool) {
	if def == nil {
		return -1, -1, false
	}
	idx := 0
	for f, i in def.fields {
		#partial switch f.kind {
		case .Label, .Markdown, .Separator, .Image:
			continue
		case:
			if idx == focus {
				return i, -1, false
			}
			idx += 1
		}
	}
	for a, i in def.actions {
		if idx == focus {
			return -1, i, true
		}
		idx += 1
		_ = a
	}
	return -1, -1, false
}
