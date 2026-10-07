// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
JSON Schema to GBNF walk for tool_grammar.odin.

Covers the subset tool parameter schemas use: string, number, integer,
boolean, null, array (items, minItems), object (properties, required,
additionalProperties), enum, const, anyOf/oneOf, allOf object merges, and
"type" given as a list. Anything unhandled falls back to the permissive val
rule so the grammar still loads.

Objects emit required keys first in sorted order, then an order free tail
that allows any subset of optional keys and, when additionalProperties is
open, free form "key": value members. The key order constraint is
intentional: grammars cannot express "any order without repetition" cheaply
and JSON objects are order insensitive for tool calls.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

@(private)
CHOICE_KEYS :: []string{"anyOf", "oneOf"}

@(private)
gbnf_schema_props :: proc(obj: json.Object) -> json.Object {
	if v, has := obj["properties"]; has {
		if po, ok := v.(json.Object); ok {
			return po
		}
	}
	return nil
}

@(private)
gbnf_schema_required :: proc(obj: json.Object, req: ^map[string]bool) {
	if v, has := obj["required"]; has {
		if arr, ok := v.(json.Array); ok {
			for item in arr {
				if s, sok := item.(json.String); sok {
					req[strings.clone(string(s), context.temp_allocator)] = true
				}
			}
		}
	}
}

@(private)
gbnf_additional_open :: proc(obj: json.Object) -> bool {
	v, has := obj["additionalProperties"]
	if !has {
		return false
	}
	#partial switch a in v {
	case json.Boolean:
		return bool(a)
	case json.Object:
		return true
	}
	return false
}

// Emit alternatives for one schema under a new sub rule, returns the rule name.
@(private)
gbnf_schema_rule :: proc(g: ^Gbnf, base: string, schema: json.Value) -> string {
	name := gbnf_sub(g, base)
	gbnf_emit_schema(g, name, schema)
	return name
}

@(private)
gbnf_emit_schema :: proc(g: ^Gbnf, name: string, schema: json.Value) {
	obj, ok := schema.(json.Object)
	if !ok {
		gbnf_rule(g, name, "val")
		return
	}
	if v, has := obj["enum"]; has {
		if arr, aok := v.(json.Array); aok && len(arr) > 0 {
			b: strings.Builder
			strings.builder_init(&b, context.temp_allocator)
			strings.write_byte(&b, '(')
			for item, i in arr {
				if i > 0 {
					strings.write_string(&b, " | ")
				}
				strings.write_string(&b, gbnf_lit_json(item))
			}
			strings.write_string(&b, ") ws")
			gbnf_rule(g, name, strings.to_string(b))
			return
		}
	}
	if v, has := obj["const"]; has {
		gbnf_rule(g, name, strings.concatenate({gbnf_lit_json(v), " ws"}, context.temp_allocator))
		return
	}
	for key in CHOICE_KEYS {
		if v, has := obj[key]; has {
			if arr, aok := v.(json.Array); aok && len(arr) > 0 {
				b: strings.Builder
				strings.builder_init(&b, context.temp_allocator)
				strings.write_byte(&b, '(')
				for item, i in arr {
					if i > 0 {
						strings.write_string(&b, " | ")
					}
					strings.write_string(&b, gbnf_schema_rule(g, name, item))
				}
				strings.write_string(&b, ") ws")
				gbnf_rule(g, name, strings.to_string(b))
				return
			}
		}
	}
	if v, has := obj["allOf"]; has {
		if arr, aok := v.(json.Array); aok && len(arr) > 0 {
			if gbnf_emit_all_of(g, name, obj, arr) {
				return
			}
		}
	}
	tv, has_type := obj["type"]
	if has_type {
		if arr, aok := tv.(json.Array); aok && len(arr) > 0 {
			// "type": [...] unions into one alternative per member type.
			b: strings.Builder
			strings.builder_init(&b, context.temp_allocator)
			strings.write_byte(&b, '(')
			wrote := 0
			for item in arr {
				s, sok := item.(json.String)
				if !sok {
					continue
				}
				if wrote > 0 {
					strings.write_string(&b, " | ")
				}
				strings.write_string(&b, gbnf_type_alt(g, name, string(s), obj))
				wrote += 1
			}
			strings.write_string(&b, ") ws")
			if wrote > 0 {
				gbnf_rule(g, name, strings.to_string(b))
				return
			}
		}
		if s, sok := tv.(json.String); sok {
			gbnf_emit_typed(g, name, string(s), obj)
			return
		}
	}
	// No usable type: infer from the keywords that are present.
	if _, has := obj["properties"]; has {
		gbnf_emit_object(g, name, obj)
	} else if _, has := obj["items"]; has {
		gbnf_emit_array(g, name, obj)
	} else {
		gbnf_rule(g, name, "val")
	}
}

// Alternative body for a single named JSON type under schema obj.
@(private)
gbnf_type_alt :: proc(g: ^Gbnf, base, typename: string, obj: json.Object) -> string {
	switch typename {
	case "string":
		return "str"
	case "integer":
		return "int"
	case "number":
		return "num"
	case "boolean":
		return "bool"
	case "null":
		return `"null"`
	case "array":
		sub := gbnf_sub(g, base)
		gbnf_emit_array(g, sub, obj)
		return sub
	case "object":
		sub := gbnf_sub(g, base)
		gbnf_emit_object(g, sub, obj)
		return sub
	}
	return "val"
}

@(private)
gbnf_emit_typed :: proc(g: ^Gbnf, name, typename: string, obj: json.Object) {
	switch typename {
	case "array":
		gbnf_emit_array(g, name, obj)
	case "object":
		gbnf_emit_object(g, name, obj)
	case:
		gbnf_rule(g, name, gbnf_type_alt(g, name, typename, obj))
	}
}

// Merge allOf entries when every member is an object shaped schema. Returns
// false when a member is not an object so the caller can fall back.
@(private)
gbnf_emit_all_of :: proc(g: ^Gbnf, name: string, obj: json.Object, arr: json.Array) -> bool {
	merged := make(json.Object, context.temp_allocator)
	req := make(map[string]bool, context.temp_allocator)
	mobjs := make([dynamic]json.Object, context.temp_allocator)
	append(&mobjs, obj)
	for item in arr {
		eo, ok := item.(json.Object)
		if !ok {
			return false
		}
		append(&mobjs, eo)
	}
	for mo in mobjs {
		for k, v in gbnf_schema_props(mo) {
			merged[strings.clone(k, context.temp_allocator)] = v
		}
		gbnf_schema_required(mo, &req)
	}
	gbnf_emit_object_parts(g, name, merged, req, gbnf_additional_open(obj))
	return true
}

@(private)
gbnf_emit_object :: proc(g: ^Gbnf, name: string, obj: json.Object) {
	req := make(map[string]bool, context.temp_allocator)
	gbnf_schema_required(obj, &req)
	gbnf_emit_object_parts(g, name, gbnf_schema_props(obj), req, gbnf_additional_open(obj))
}

@(private)
gbnf_emit_object_parts :: proc(
	g: ^Gbnf,
	name: string,
	props: json.Object,
	req: map[string]bool,
	open: bool,
) {
	if len(props) == 0 {
		// No declared properties means free form args, keep it permissive.
		gbnf_rule(g, name, "any-obj")
		return
	}
	keys := make([dynamic]string, context.temp_allocator)
	for k in props {
		append(&keys, k)
	}
	slice.sort_by(keys[:], proc(a, b: string) -> bool { return strings.compare(a, b) < 0 })
	req_keys := make([dynamic]string, context.temp_allocator)
	opt_keys := make([dynamic]string, context.temp_allocator)
	for k in keys {
		if req[k] {
			append(&req_keys, k)
		} else {
			append(&opt_keys, k)
		}
	}
	// Value rules per property, indexed by sorted key.
	pi := make(map[string]string, context.temp_allocator)
	for k in keys {
		pi[strings.clone(k, context.temp_allocator)] = gbnf_schema_rule(g, name, props[k])
	}
	kv :: proc(k, prule: string) -> string {
		// Marshal gives the JSON encoded key ("k"), the literal matches the
		// wire bytes including the quotes.
		key := gbnf_lit_json(json.String(strings.clone(k, context.temp_allocator)))
		return strings.concatenate({key, ` ws ":" ws `, prule}, context.temp_allocator)
	}
	// Optional tail: any subset of optional keys, plus free extras when open.
	alts := make([dynamic]string, context.temp_allocator)
	for k in opt_keys {
		append(&alts, kv(k, pi[k]))
	}
	if open {
		append(&alts, `str ":" ws val`)
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `"{" ws `)
	if len(req_keys) > 0 {
		for k, i in req_keys {
			if i > 0 {
				strings.write_string(&b, `"," ws `)
			}
			strings.write_string(&b, kv(k, pi[k]))
		}
		if len(alts) > 0 {
			strings.write_string(&b, ` ("," ws (`)
			for a, i in alts {
				if i > 0 {
					strings.write_string(&b, " | ")
				}
				strings.write_string(&b, a)
			}
			strings.write_string(&b, `))*`)
		}
	} else {
		strings.write_string(&b, `( (`)
		for a, i in alts {
			if i > 0 {
				strings.write_string(&b, " | ")
			}
			strings.write_string(&b, a)
		}
		strings.write_string(&b, `) ("," ws (`)
		for a, i in alts {
			if i > 0 {
				strings.write_string(&b, " | ")
			}
			strings.write_string(&b, a)
		}
		strings.write_string(&b, `))* )?`)
	}
	strings.write_string(&b, ` "}" ws`)
	gbnf_rule(g, name, strings.to_string(b))
}

@(private)
gbnf_emit_array :: proc(g: ^Gbnf, name: string, obj: json.Object) {
	item_rule := "val"
	if v, has := obj["items"]; has {
		item_rule = gbnf_schema_rule(g, name, v)
	}
	min_items := 0
	if v, has := obj["minItems"]; has {
		#partial switch n in v {
		case json.Integer:
			min_items = int(n)
		case json.Float:
			min_items = int(n)
		}
	}
	body: string
	if min_items >= 1 {
		body = fmt.tprintf(`"[" ws %s ("," ws %s)* "]" ws`, item_rule, item_rule)
	} else {
		body = fmt.tprintf(`"[" ws ( %s ("," ws %s)* )? "]" ws`, item_rule, item_rule)
	}
	gbnf_rule(g, name, body)
}
