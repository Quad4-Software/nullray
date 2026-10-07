// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
PA-Tool probe (arxiv 2510.07248): measure which tool-name spelling a model
produces most reliably, then persist the winners as a tool_names table on
its model_profiles.json entry.

Per target tool the probe advertises one candidate name at a time (canonical
plus common variants), samples the model N times demanding a call, and counts
how often the emitted call uses the advertised name with parseable args. The
highest-scoring candidate wins; a canonical winner means no rename, anything
else becomes an alias entry. probe_name_candidates, probe_tally and
probe_pick_winner are pure so the measurement logic is testable without a
live server.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"

PROBE_SAMPLES_DEFAULT :: 3

// One tool to probe: canonical name, its parameters schema, and a canned
// argument example the prompt asks the model to use.
Probe_Target :: struct {
	name:        string,
	schema_json: string,
	args_hint:   string,
}

// Per-candidate counters for one target.
Probe_Variant :: struct {
	advertised: string,
	calls:      int, // samples that produced any tool call
	name_hits:  int, // emitted name == advertised name
	valid_args: int, // name hit and arguments parsed to a JSON object
}

// Outcome of the whole probe, ready for the CLI to print and persist.
Probe_Report :: struct {
	provider_id: string,
	model:       string,
	rows:        [dynamic]Probe_Variant,
	row_tool:    [dynamic]string, // canonical name per row, same indexing
	aliases:     map[string]string,
}

/*
Name spellings a model may prefer, ordered canonical first so a scoring tie
keeps the canonical name and no alias is written. Variants: camelCase,
PascalCase, kebab-case, and the flattened no-separator form.
*/
probe_name_candidates :: proc(canonical: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	append(&out, strings.clone(canonical, allocator))
	// camelCase: drop separators, upper the letter after each one.
	camel: strings.Builder
	strings.builder_init(&camel, allocator)
	pascal: strings.Builder
	strings.builder_init(&pascal, allocator)
	kebab, _ := strings.replace_all(canonical, "_", "-", allocator)
	flat: strings.Builder
	strings.builder_init(&flat, allocator)
	upper_next := false
	first := true
	for c in canonical {
		if c == '_' || c == '-' {
			upper_next = true
			continue
		}
		lc := c
		if c >= 'A' && c <= 'Z' {
			lc = c + ('a' - 'A')
		}
		strings.write_byte(&flat, u8(lc))
		up := lc
		if (upper_next || first) && lc >= 'a' && lc <= 'z' {
			up = lc - ('a' - 'A')
		}
		if upper_next {
			strings.write_byte(&camel, u8(up))
		} else {
			strings.write_byte(&camel, u8(lc))
		}
		strings.write_byte(&pascal, u8(up))
		upper_next = false
		first = false
	}
	cand := [3]string{strings.to_string(camel), strings.to_string(pascal), kebab}
	seen := make(map[string]bool, context.temp_allocator)
	seen[canonical] = true
	for c in cand {
		if len(c) > 0 && !seen[c] {
			seen[c] = true
			append(&out, c)
		}
	}
	f := strings.to_string(flat)
	if len(f) > 0 && !seen[f] {
		append(&out, f)
	}
	return out[:]
}

// Fold one sample into the tally: emitted is the first tool-call name the
// model produced, args_obj says its arguments parsed to a JSON object.
probe_tally :: proc(v: ^Probe_Variant, emitted: string, args_obj: bool) {
	if len(emitted) == 0 {
		return
	}
	v.calls += 1
	if emitted == v.advertised {
		v.name_hits += 1
		if args_obj {
			v.valid_args += 1
		}
	}
}

/*
Winning advertised name for one target: most name_hits, ties resolve to the
earlier candidate (canonical sits first, so a tie keeps the canonical name).
Returns "" when no candidate ever produced a correctly-named call.
*/
probe_pick_winner :: proc(variants: []Probe_Variant) -> string {
	best := ""
	best_hits := 0
	for v in variants {
		if v.name_hits > best_hits {
			best_hits = v.name_hits
			best = v.advertised
		}
	}
	return best
}

@(private)
probe_args_object :: proc(args: string) -> bool {
	v, perr := json.parse_string(args, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return false
	}
	_, ok := v.(json.Object)
	return ok
}

@(private)
probe_tools_entry_json :: proc(name, schema_json: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `[{"type":"function","function":{"name":`)
	write_json_string(&b, name)
	strings.write_string(&b, `,"description":"Probe target","parameters":`)
	schema := strings.trim_space(schema_json)
	if len(schema) == 0 {
		schema = `{"type":"object","properties":{}}`
	}
	strings.write_string(&b, schema)
	strings.write_string(&b, "}}]")
	return strings.to_string(b)
}

/*
One probe sample: offer the target under the candidate name, demand the call,
record the emitted name and whether arguments parsed. Returns ok=false on a
transport or provider error, the sample then counts for nothing.
*/
@(private)
probe_sample_once :: proc(
	p: ^Provider,
	model: string,
	candidate: string,
	tools_json: string,
	args_hint: string,
	allocator := context.allocator,
) -> (emitted: string, args_obj: bool, ok: bool) {
	hint := strings.trim_space(args_hint)
	if len(hint) == 0 {
		hint = "{}"
	}
	system := fmt.aprintf(
		`You must call the function named "%s" exactly once with JSON arguments %s. Do not reply with text.`,
		candidate,
		hint,
		allocator = context.temp_allocator,
	)
	msgs := []Message{
		{role = .System, content = system},
		{role = .User, content = "call it now"},
	}
	req := Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		tools_json = tools_json,
		tool_choice = "auto",
		max_tokens = constants.MODEL_SMOKE_MAX_TOKENS,
		temperature = 0,
		temperature_set = true,
	}
	res := p.chat(p, req, allocator)
	defer destroy_chat_response(&res)
	if !res.ok {
		return "", false, false
	}
	if len(res.tool_calls) == 0 {
		return "", false, true
	}
	tc := res.tool_calls[0]
	return tc.name, probe_args_object(tc.arguments), true
}

/*
Run the probe: every target x every candidate x samples chats. Returns the
report; aliases maps canonical -> winning non-canonical name only, so an
empty map means the model already prefers the shipped names.
*/
probe_tools_run :: proc(
	p: ^Provider,
	model: string,
	targets: []Probe_Target,
	samples := PROBE_SAMPLES_DEFAULT,
	allocator := context.allocator,
) -> Probe_Report {
	rep: Probe_Report
	rep.provider_id = p != nil ? p.id : ""
	rep.model = strings.clone(model, allocator)
	rep.aliases = make(map[string]string, allocator)
	if p == nil || p.chat == nil || len(model) == 0 || samples <= 0 {
		return rep
	}
	for tgt in targets {
		cands := probe_name_candidates(tgt.name, context.temp_allocator)
		variants := make([]Probe_Variant, len(cands), context.temp_allocator)
		for c, i in cands {
			variants[i].advertised = strings.clone(c, allocator)
		}
		for c, i in cands {
			tools_json := probe_tools_entry_json(c, tgt.schema_json, context.temp_allocator)
			for _ in 0 ..< samples {
				emitted, args_obj, ok := probe_sample_once(p, model, c, tools_json, tgt.args_hint, allocator)
				if !ok {
					continue
				}
				probe_tally(&variants[i], emitted, args_obj)
			}
		}
		for v in variants {
			append(&rep.rows, v)
			append(&rep.row_tool, strings.clone(tgt.name, allocator))
		}
		if winner := probe_pick_winner(variants); len(winner) > 0 && winner != tgt.name {
			rep.aliases[strings.clone(tgt.name, allocator)] = strings.clone(winner, allocator)
		}
	}
	return rep
}
