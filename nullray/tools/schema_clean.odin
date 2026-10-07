// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tool schema hygiene for providers with weak constrained-decoding grammars
(llama.cpp, ollama). Their grammars spend slots on every constraint keyword,
so we strip the ones that never change which parameters exist: $schema,
$defs, definitions, and the string/constraint annotations maxLength,
minLength, pattern, format, uniqueItems, examples.

$ref is deliberately kept even though stripping $defs can leave it dangling:
dropping the ref would silently delete the parameter schema it points at,
while a dangling ref is ignored by the servers this targets. Nothing else is
removed, dropping properties would break real tool calls. Parse failures fail
open and return the input unchanged.

Gate: NULLRAY_SCHEMA_CLEAN=1 forces on for any provider, =0 forces off, and
unset auto-enables for llamacpp and ollama provider ids.
*/

package tools

import "core:encoding/json"
import "core:os"
import "core:slice"
import "core:strings"
import "nullray:constants"

SCHEMA_CLEAN_PROVIDER_IDS :: []string{"llamacpp", "ollama"}

SCHEMA_STRIP_KEYS :: []string{
	"$defs",
	"definitions",
	"$schema",
	"maxLength",
	"minLength",
	"pattern",
	"format",
	"uniqueItems",
	"examples",
}

schema_clean_enabled :: proc(provider_id := "") -> bool {
	if v, ok := os.lookup_env(constants.ENV_SCHEMA_CLEAN, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "", "0", "false", "no", "off":
			return false
		case:
			return true
		}
	}
	for id in SCHEMA_CLEAN_PROVIDER_IDS {
		if id == provider_id {
			return true
		}
	}
	return false
}

@(private)
schema_strip_key :: proc(k: string) -> bool {
	for s in SCHEMA_STRIP_KEYS {
		if k == s {
			return true
		}
	}
	return false
}

// Re-serializes the schema with strip keys removed at every depth. On any
// parse or marshal failure the original text is cloned back out (fail open).
schema_sanitize :: proc(schema: string, allocator := context.allocator) -> string {
	doc, perr := json.parse_string(schema, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return strings.clone(schema, allocator)
	}
	cleaned := schema_sanitize_clone(doc, context.temp_allocator)
	b := strings.builder_make(allocator)
	json_emit_sorted(cleaned, &b)
	return strings.to_string(b)
}

@(private)
schema_sanitize_clone :: proc(v: json.Value, allocator := context.allocator) -> json.Value {
	#partial switch val in v {
	case json.Object:
		out := make(json.Object, allocator = allocator)
		for k, child in val {
			if schema_strip_key(k) {
				continue
			}
			out[strings.clone(k, allocator)] = schema_sanitize_clone(child, allocator)
		}
		return out
	case json.Array:
		out := make(json.Array, 0, len(val), allocator)
		for item in val {
			append(&out, schema_sanitize_clone(item, allocator))
		}
		return out
	case json.String:
		return strings.clone(val, allocator)
	}
	return v
}

/*
json emission with object keys sorted. Odin json.unparse iterates the map in
hash order seeded by allocation address, so two identical schemas could emit
different bytes and break provider prefix caching. Deterministic emission
keeps the tools JSON byte-stable across builds and calls.
*/
json_emit_sorted :: proc(v: json.Value, b: ^strings.Builder) {
	#partial switch val in v {
	case json.Object:
		strings.write_byte(b, '{')
		keys := make([dynamic]string, context.temp_allocator)
		for k in val {
			append(&keys, k)
		}
		slice.sort_by(keys[:], proc(a, b: string) -> bool { return strings.compare(a, b) < 0 })
		for k, i in keys[:] {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			ks, _ := json.marshal(k, allocator = context.temp_allocator)
			strings.write_string(b, string(ks))
			strings.write_byte(b, ':')
			json_emit_sorted(val[k], b)
		}
		strings.write_byte(b, '}')
	case json.Array:
		strings.write_byte(b, '[')
		for item, i in val {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			json_emit_sorted(item, b)
		}
		strings.write_byte(b, ']')
	case:
		data, _ := json.marshal(v, allocator = context.temp_allocator)
		strings.write_string(b, string(data))
	}
}
