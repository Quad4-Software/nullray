// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
External agent CLI harnesses: preset table, detection, enable gate.

A Harness delegates one prompt to another agent CLI installed on the host
(claude, opencode, gemini, codex, aider, goose, crush, pi). Presets are data,
not hardcoded exec: a wrong flag is fixable in harnesses.json without a
rebuild. Config merge lives in parse.odin, process capture in run.odin.
*/

package harness

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

Output_Mode :: enum {
	// Raw stdout is the result.
	Text,
	// Best-effort pull of a result/output/text field from the last JSON object.
	Json,
}

Source :: enum {
	Builtin,
	Config,
	Workspace,
}

Harness :: struct {
	id:          string,
	name:        string,
	// Binary name or absolute path from the preset or config entry.
	bin:         string,
	// Resolved executable path, "" until detect finds it.
	binary:      string,
	// Argument template, {prompt} and {cwd} are substituted per element.
	argv:        [dynamic]string,
	output:      Output_Mode,
	timeout_sec: int,
	source:      Source,
}

Preset :: struct {
	id:    string,
	name:  string,
	bin:   string,
	argv:  []string,
	mode:  Output_Mode,
	notes: string,
}

/*
Non-interactive argv for the well-known agent CLIs. The prompt is always one
argv element substituted for {prompt}, no shell ever sees it.
*/
BUILTIN_PRESETS :: []Preset{
	{id = "claude", name = "Claude Code", bin = "claude",
	 argv = {"-p", "{prompt}", "--output-format", "text"},
	 mode = .Text, notes = "print mode, plain text on stdout"},
	{id = "opencode", name = "OpenCode", bin = "opencode",
	 argv = {"run", "{prompt}"},
	 mode = .Text, notes = "run subcommand is non-interactive"},
	{id = "gemini", name = "Gemini CLI", bin = "gemini",
	 argv = {"-p", "{prompt}", "--output-format", "text"},
	 mode = .Text, notes = "-p selects non-interactive prompt mode"},
	{id = "codex", name = "Codex", bin = "codex",
	 argv = {"exec", "{prompt}"},
	 mode = .Text, notes = "exec runs headless"},
	{id = "aider", name = "Aider", bin = "aider",
	 argv = {"--message", "{prompt}", "--yes", "--no-git"},
	 mode = .Text, notes = "one-shot message, auto-confirm, no git"},
	{id = "goose", name = "Goose", bin = "goose",
	 argv = {"run", "-t", "{prompt}"},
	 mode = .Text, notes = "run -t carries the instruction text"},
	{id = "crush", name = "Crush", bin = "crush",
	 argv = {"run", "--quiet", "{prompt}"},
	 mode = .Text, notes = "run is non-interactive, --quiet hides the spinner"},
	{id = "pi", name = "Pi", bin = "pi",
	 argv = {"-p", "{prompt}"},
	 mode = .Text, notes = "-p prints the reply and exits"},
}

HARNESS_DISABLED :: "external harnesses disabled (NULLRAY_HARNESS=0)"

// NULLRAY_HARNESS=0/false/no/off disables the harness tools entirely.
harness_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HARNESS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}

/*
Free every owned field and the slice. Only for lists built by load_harnesses,
all fields live on the passed allocator.
*/
harnesses_destroy :: proc(list: []Harness, allocator := context.allocator) {
	for h in list {
		harness_destroy(h, allocator)
	}
	delete(list, allocator)
}

harness_destroy :: proc(h: Harness, allocator := context.allocator) {
	delete(h.id, allocator)
	delete(h.name, allocator)
	delete(h.bin, allocator)
	delete(h.binary, allocator)
	for a in h.argv {
		delete(a, allocator)
	}
	delete(h.argv)
}

harness_find :: proc(list: []Harness, id: string) -> (^Harness, bool) {
	for &h in list {
		if h.id == id {
			return &h, true
		}
	}
	return nil, false
}

/*
Resolve each configured bin to an absolute path. Absolute or relative paths
with a slash are checked on disk, bare names scan PATH with system dirs first
so sandboxed exec resolves the same order children get (see hooks.hook_env).
*/
detect :: proc(list: []Harness, allocator := context.allocator) {
	for &h in list {
		if len(h.binary) > 0 || len(h.bin) == 0 {
			continue
		}
		if path, ok := resolve_bin(h.bin, allocator); ok {
			h.binary = path
		}
	}
}

resolve_bin :: proc(bin: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if len(bin) == 0 {
		return "", false
	}
	if strings.contains(bin, "/") || strings.contains(bin, `\`) {
		if os.exists(bin) {
			abs, aerr := filepath.abs(bin, allocator)
			if aerr == nil {
				return abs, true
			}
			return strings.clone(bin, allocator), true
		}
		return "", false
	}
	path_env, found := os.lookup_env("PATH", context.temp_allocator)
	search := make([dynamic]string, context.temp_allocator)
	append(&search, "/usr/local/bin", "/usr/bin", "/bin")
	if found && len(path_env) > 0 {
		copy := path_env
		for part in strings.split_iterator(&copy, ":") {
			dir := strings.trim_space(part)
			if len(dir) == 0 {
				continue
			}
			dup := false
			for s in search {
				if s == dir {
					dup = true
					break
				}
			}
			if !dup {
				append(&search, dir)
			}
		}
	}
	for dir in search {
		cand, jerr := filepath.join({dir, bin}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if os.exists(cand) {
			return strings.clone(cand, allocator), true
		}
	}
	return "", false
}

/*
Text table for the harness_list tool: id, display name, resolved binary or
"not found", and the config source.
*/
list_available :: proc(allocator := context.allocator) -> string {
	list := load_harnesses(allocator)
	defer harnesses_destroy(list, allocator)
	detect(list, allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for h in list {
		src := "builtin"
		switch h.source {
		case .Config:
			src = "config"
		case .Workspace:
			src = "workspace"
		case .Builtin:
		}
		bin := h.binary
		if len(bin) == 0 {
			bin = "not found"
		}
		strings.write_string(&b, h.id)
		strings.write_string(&b, "\t")
		strings.write_string(&b, bin)
		strings.write_string(&b, "\t")
		strings.write_string(&b, src)
		if len(h.name) > 0 && h.name != h.id {
			strings.write_string(&b, "\t")
			strings.write_string(&b, h.name)
		}
		strings.write_string(&b, "\n")
	}
	return strings.to_string(b)
}
