// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(private)
probe_profiles_free :: proc(profiles: []Model_Profile) {
	for p in profiles {
		delete(p.match)
		for k, v in p.tool_names {
			delete(k)
			delete(v)
		}
		delete(p.tool_names)
	}
	delete(profiles)
}

@(private)
probe_report_free :: proc(rep: ^Probe_Report) {
	delete(rep.model)
	for k, v in rep.aliases {
		delete(k)
		delete(v)
	}
	delete(rep.aliases)
	for r in rep.rows {
		delete(r.advertised)
	}
	for s in rep.row_tool {
		delete(s)
	}
	delete(rep.rows)
	delete(rep.row_tool)
}

@(test)
test_probe_name_candidates :: proc(t: ^testing.T) {
	c := probe_name_candidates("read_file", context.temp_allocator)
	testing.expect_value(t, len(c), 5)
	testing.expect_value(t, c[0], "read_file")
	testing.expect_value(t, c[1], "readFile")
	testing.expect_value(t, c[2], "ReadFile")
	testing.expect_value(t, c[3], "read-file")
	testing.expect_value(t, c[4], "readfile")

	// No separators: variants dedupe away, canonical stays first.
	c2 := probe_name_candidates("scaffold", context.temp_allocator)
	testing.expect_value(t, len(c2), 2)
	testing.expect_value(t, c2[0], "scaffold")
	testing.expect_value(t, c2[1], "Scaffold")
}

@(test)
test_probe_tally_and_winner :: proc(t: ^testing.T) {
	variants := []Probe_Variant{
		{advertised = "read_file"},
		{advertised = "readFile"},
		{advertised = "read-file"},
	}
	// Canonical: one hit, one miss. camelCase: two hits.
	probe_tally(&variants[0], "read_file", true)
	probe_tally(&variants[0], "other", false)
	probe_tally(&variants[1], "readFile", true)
	probe_tally(&variants[1], "readFile", true)
	testing.expect_value(t, variants[0].calls, 2)
	testing.expect_value(t, variants[0].name_hits, 1)
	testing.expect_value(t, variants[0].valid_args, 1)
	testing.expect_value(t, variants[1].name_hits, 2)
	testing.expect_value(t, variants[1].valid_args, 2)
	testing.expect_value(t, probe_pick_winner(variants), "readFile")

	// Tie keeps the earlier candidate, canonical listed first stays put.
	probe_tally(&variants[0], "read_file", true)
	testing.expect_value(t, probe_pick_winner(variants), "read_file")

	// No correct calls at all: no winner.
	empty := []Probe_Variant{{advertised = "x"}}
	testing.expect_value(t, probe_pick_winner(empty), "")
}

@(test)
test_profile_tool_names_parse_and_serialize :: proc(t: ^testing.T) {
	text := `{"profiles":[{"match":"qwen*","tool_names":{"read_file":"readFile","run_shell":"shell"}}]}`
	profiles := profile_parse(text, context.allocator)
	defer probe_profiles_free(profiles)
	testing.expect_value(t, len(profiles), 1)
	testing.expect_value(t, len(profiles[0].tool_names), 2)
	testing.expect_value(t, profiles[0].tool_names["read_file"], "readFile")
	testing.expect_value(t, profiles[0].tool_names["run_shell"], "shell")

	// Serialize then reparse: the table round-trips.
	out := profile_serialize(profiles, context.allocator)
	defer delete(out)
	again := profile_parse(out, context.allocator)
	defer probe_profiles_free(again)
	testing.expect_value(t, len(again), 1)
	testing.expect_value(t, len(again[0].tool_names), 2)
	testing.expect_value(t, again[0].tool_names["read_file"], "readFile")
}

@(test)
test_profile_save_tool_names_roundtrip :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.temp_allocator)
	dir, _ := filepath.join({tmp, "nullray-probe-cfg"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	saved, had := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator)
	defer if had {
		os.set_env("XDG_CONFIG_HOME", saved)
	} else {
		os.unset_env("XDG_CONFIG_HOME")
	}
	os.set_env("XDG_CONFIG_HOME", dir)

	tn := make(map[string]string, context.temp_allocator)
	tn["read_file"] = "readFile"
	path, err := profile_save_tool_names("probe-model", tn, context.allocator)
	testing.expect_value(t, err, "")
	defer delete(path)
	testing.expect(t, os.is_file(path))

	// Update path preserves other fields and other profiles.
	path2, err2 := profile_save_tool_names("other-model", tn, context.allocator)
	testing.expect_value(t, err2, "")
	defer delete(path2)
	data, rerr := os.read_entire_file(path2, context.temp_allocator)
	testing.expect(t, rerr == nil)
	profiles := profile_parse(string(data), context.allocator)
	defer probe_profiles_free(profiles)
	testing.expect_value(t, len(profiles), 2)
	for p in profiles {
		testing.expect_value(t, len(p.tool_names), 1)
		testing.expect_value(t, p.tool_names["read_file"], "readFile")
	}
}

// Fake chat that emits one call named after a scripted per-candidate table.
@(private)
Probe_Fake :: struct {
	emit:  map[string]string,
	calls: int,
}

@(private)
probe_fake_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
	f := cast(^Probe_Fake)p.user_data
	f.calls += 1
	res := Chat_Response{ok = true}
	name := ""
	if idx := strings.index(req.tools_json, `"name":"`); idx >= 0 {
		rest := req.tools_json[idx + len(`"name":"`):]
		if end := strings.index(rest, `"`); end >= 0 {
			name = rest[:end]
		}
	}
	want := name
	if f.emit != nil {
		if scripted, ok := f.emit[name]; ok {
			want = scripted
		}
	}
	if len(want) > 0 {
		res.tool_calls = make([]Tool_Call, 1, allocator)
		res.tool_calls[0] = Tool_Call{
			id = strings.clone("c1", allocator),
			name = strings.clone(want, allocator),
			arguments = strings.clone(`{"x":1}`, allocator),
		}
	}
	return res
}

@(test)
test_probe_tools_run_picks_alias :: proc(t: ^testing.T) {
	// Model prefers camelCase for read_file whatever is advertised.
	emit := make(map[string]string, context.temp_allocator)
	for c in probe_name_candidates("read_file", context.temp_allocator) {
		emit[c] = "readFile"
	}
	f := Probe_Fake{emit = emit}
	p := Provider{id = "ollama", chat = probe_fake_chat, user_data = &f}
	targets := []Probe_Target{
		{name = "read_file", schema_json = `{"type":"object","properties":{"x":{"type":"string"}}}`, args_hint = `{"x":"1"}`},
	}
	rep := probe_tools_run(&p, "m", targets, 2, context.allocator)
	defer probe_report_free(&rep)
	testing.expect_value(t, len(rep.rows), 5)
	testing.expect_value(t, len(rep.aliases), 1)
	testing.expect_value(t, rep.aliases["read_file"], "readFile")
	// Canonical advertised scored 0 hits, camelCase scored 2.
	testing.expect_value(t, rep.rows[0].name_hits, 0)
	testing.expect_value(t, rep.rows[1].name_hits, 2)
}

@(test)
test_probe_tools_run_canonical_wins :: proc(t: ^testing.T) {
	// Model echoes the advertised name: canonical ties and wins on order.
	f := Probe_Fake{}
	p := Provider{id = "ollama", chat = probe_fake_chat, user_data = &f}
	targets := []Probe_Target{
		{name = "read_file", schema_json = `{"type":"object"}`, args_hint = "{}"},
	}
	rep := probe_tools_run(&p, "m", targets, 1, context.allocator)
	defer probe_report_free(&rep)
	testing.expect_value(t, len(rep.aliases), 0)
	for r in rep.rows {
		testing.expect_value(t, r.name_hits, 1)
	}
}
