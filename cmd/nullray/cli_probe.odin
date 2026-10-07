// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package main

import "core:fmt"
import "core:strings"
import "nullray:http"
import "nullray:provider"
import "nullray:tools"

/*
--probe-tools [provider/model]: PA-Tool probe. For each core tool the probe
advertises candidate name spellings (canonical, camelCase, PascalCase,
kebab-case, flat) one at a time, samples the model --samples N (default 3)
times demanding a call, and counts which advertised names come back. Winning
non-canonical names are written to the model's tool_names table in
model_profiles.json, so later runs alias them via the PA-Tool rename path.
*/

// Small core set keeps the request count bounded, extend as needed.
PROBE_TOOL_SET :: []string{
	"read_file",
	"write_file",
	"edit_file",
	"list_dir",
	"grep_files",
	"glob_files",
	"run_shell",
}

// Canned argument examples per probed tool, only carried in the prompt.
probe_args_hint :: proc(name: string) -> string {
	switch name {
	case "read_file":
		return `{"path":"README.md"}`
	case "write_file":
		return `{"path":"tmp_probe.txt","content":"ping"}`
	case "edit_file":
		return `{"path":"tmp_probe.txt","old_string":"a","new_string":"b"}`
	case "list_dir":
		return `{"path":"."}`
	case "grep_files":
		return `{"pattern":"probe"}`
	case "glob_files":
		return `{"pattern":"*.txt"}`
	case "run_shell":
		return `{"command":"echo ping"}`
	}
	return "{}"
}

// Split [provider/model]: "p/m" picks both, "m" keeps the active provider,
// "auto" or "" keeps env selection and the provider default model.
probe_resolve_target :: proc(reg: ^provider.Registry, arg: string) -> (p: ^provider.Provider, model: string) {
	want_p := ""
	want_m := ""
	if arg != "auto" && len(arg) > 0 {
		if idx := strings.index(arg, "/"); idx >= 0 {
			want_p = arg[:idx]
			want_m = arg[idx + 1:]
		} else if _, ok := provider.registry_find(reg, provider.normalize_provider_id(arg)); ok {
			want_p = arg
		} else {
			want_m = arg
		}
	}
	if len(want_p) > 0 {
		if found, ok := provider.registry_find(reg, provider.normalize_provider_id(want_p)); ok {
			p = found
		}
	}
	if p == nil {
		p = provider.registry_active(reg)
	}
	model = want_m
	if len(model) == 0 && p != nil {
		model = p.default_model
	}
	return p, model
}

run_probe_tools :: proc(cli: ^Cli) -> int {
	if !http.global_init() {
		fmt.eprintln("nullray: TLS init failed")
		return 1
	}
	defer http.global_cleanup()

	preg: provider.Registry
	provider.registry_init(&preg)
	defer provider.registry_destroy(&preg)

	p, model := probe_resolve_target(&preg, cli.probe_tools)
	if p == nil || p.chat == nil {
		fmt.eprintln("nullray: probe-tools: no provider")
		return 1
	}
	if len(model) == 0 {
		fmt.eprintln("nullray: probe-tools: no model (pass provider/model or --model)")
		return 1
	}

	tools.tools_init()
	defer tools.tools_destroy()
	targets := make([dynamic]provider.Probe_Target, context.temp_allocator)
	for name in PROBE_TOOL_SET {
		if t, ok := tools.find(name); ok {
			append(&targets, provider.Probe_Target{
				name = name,
				schema_json = t.schema_json,
				args_hint = probe_args_hint(name),
			})
		}
	}
	if len(targets) == 0 {
		fmt.eprintln("nullray: probe-tools: no probed tools registered")
		return 1
	}
	samples := cli.samples
	if samples <= 0 {
		samples = provider.PROBE_SAMPLES_DEFAULT
	}
	fmt.printf("probing %s (%s) model %s, %d tool(s) x %d sample(s)\n", p.name, p.id, model, len(targets), samples)
	rep := provider.probe_tools_run(p, model, targets[:], samples, context.allocator)

	last_tool := ""
	had_call := false
	for v, i in rep.rows {
		tool := rep.row_tool[i]
		if tool != last_tool {
			fmt.printf("%s\n", tool)
			last_tool = tool
		}
		fmt.printf("  %-16s hits=%d calls=%d\n", v.advertised, v.name_hits, v.calls)
		if v.calls > 0 {
			had_call = true
		}
	}
	if !had_call {
		fmt.eprintln("nullray: probe-tools: model emitted no tool calls; is the server reachable?")
		return 1
	}
	if len(rep.aliases) == 0 {
		fmt.println("canonical names already win; no tool_names written")
		return 0
	}
	path, serr := provider.profile_save_tool_names(model, rep.aliases, context.temp_allocator)
	if len(serr) > 0 {
		fmt.eprintln("nullray: probe-tools:", serr)
		return 1
	}
	// Reload so the saved table is live for this process too.
	_ = provider.profile_load()
	fmt.printf("wrote %d alias(es) to %s\n", len(rep.aliases), path)
	for canonical, alias in rep.aliases {
		fmt.printf("  %s -> %s\n", canonical, alias)
	}
	return 0
}
