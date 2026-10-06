// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
restore_schema_clean_env :: proc(saved: string, had: bool) {
	if had {
		os.set_env(constants.ENV_SCHEMA_CLEAN, saved)
	} else {
		os.unset_env(constants.ENV_SCHEMA_CLEAN)
	}
}

@(test)
test_schema_sanitize_strips_constraint_keys :: proc(t: ^testing.T) {
	src := `{"type":"object","$schema":"http://json-schema.org/draft-07/schema#",` +
		`"properties":{"name":{"type":"string","maxLength":10,"minLength":1,` +
		`"pattern":"^[a-z]+$","format":"email","description":"n"},` +
		`"tags":{"type":"array","uniqueItems":true,"examples":["a"],` +
		`"items":{"type":"string","minLength":1}}},` +
		`"definitions":{"x":{"type":"string"}},"$defs":{"y":{"type":"string"}},` +
		`"required":["name"]}`
	out := schema_sanitize(src, context.allocator)
	defer delete(out)

	for k in ([]string{
		`"$schema"`, `"maxLength"`, `"minLength"`, `"pattern"`, `"format"`,
		`"uniqueItems"`, `"examples"`, `"definitions"`, `"$defs"`,
	}) {
		testing.expect(t, !strings.contains(out, k))
	}
	testing.expect(t, strings.contains(out, `"type"`))
	testing.expect(t, strings.contains(out, `"properties"`))
	testing.expect(t, strings.contains(out, `"description"`))
	testing.expect(t, strings.contains(out, `"required"`))
	testing.expect(t, strings.contains(out, `"name"`))
	testing.expect(t, strings.contains(out, `"tags"`))
	// Output still parses and stays an object.
	doc, perr := json.parse_string(out, .JSON, allocator = context.temp_allocator)
	testing.expect(t, perr == .None)
	_, is_obj := doc.(json.Object)
	testing.expect(t, is_obj)
}

@(test)
test_schema_sanitize_keeps_ref_and_enum :: proc(t: ^testing.T) {
	src := `{"type":"object","properties":{"mode":{"enum":["a","b"]},"ref":{"$ref":"#/$defs/x"}}}`
	out := schema_sanitize(src, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, `"$ref"`))
	testing.expect(t, strings.contains(out, `"enum"`))
}

@(test)
test_schema_sanitize_fail_open :: proc(t: ^testing.T) {
	bad := `{"type": "object",`
	out := schema_sanitize(bad, context.allocator)
	defer delete(out)
	testing.expect(t, out == bad)
}

@(test)
test_schema_clean_enabled :: proc(t: ^testing.T) {
	saved, had := os.lookup_env(constants.ENV_SCHEMA_CLEAN, context.temp_allocator)
	defer restore_schema_clean_env(saved, had)
	os.unset_env(constants.ENV_SCHEMA_CLEAN)

	testing.expect(t, schema_clean_enabled("llamacpp"))
	testing.expect(t, schema_clean_enabled("ollama"))
	testing.expect(t, !schema_clean_enabled("openai"))
	testing.expect(t, !schema_clean_enabled(""))

	os.set_env(constants.ENV_SCHEMA_CLEAN, "1")
	testing.expect(t, schema_clean_enabled("openai"))
	os.set_env(constants.ENV_SCHEMA_CLEAN, "0")
	testing.expect(t, !schema_clean_enabled("llamacpp"))
	os.unset_env(constants.ENV_SCHEMA_CLEAN)
}

@(test)
test_openai_tools_json_sanitizes_for_llamacpp :: proc(t: ^testing.T) {
	saved, had := os.lookup_env(constants.ENV_SCHEMA_CLEAN, context.temp_allocator)
	defer restore_schema_clean_env(saved, had)
	os.unset_env(constants.ENV_SCHEMA_CLEAN)

	reg: Registry
	reg.tools = make([dynamic]Tool)
	defer delete(reg.tools)
	registry_register(&reg, Tool{
		name = "demo",
		description = "d",
		schema_json = `{"type":"object","properties":{"path":{"type":"string","maxLength":10,"pattern":"^x$","description":"p"}},"required":["path"]}`,
		kind = .Read,
	})

	dirty := openai_tools_json(&reg, "edit", .Full, context.allocator, nil, "openai")
	defer delete(dirty)
	testing.expect(t, strings.contains(dirty, `"maxLength"`))

	clean := openai_tools_json(&reg, "edit", .Full, context.allocator, nil, "llamacpp")
	defer delete(clean)
	testing.expect(t, !strings.contains(clean, `"maxLength"`))
	testing.expect(t, !strings.contains(clean, `"pattern"`))
	testing.expect(t, strings.contains(clean, `"path"`))
	testing.expect(t, strings.contains(clean, `"required"`))
}
