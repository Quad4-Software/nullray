// SPDX-License-Identifier: 0BSD
/*
Coding agent system prompt, AGENTS.md load, and tool catalog injection.
*/

package agent

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:skills"
import "nullray:tools"

CODING_AGENT_PREAMBLE :: `You are nullray, an autonomous coding agent running in a sandboxed workspace.

Goals:
- Solve the user's task by reading, editing, searching, and running commands as needed.
- Prefer small precise edits (edit_file / apply_edits) over rewriting whole files.
- Use grep_files and glob_files before large reads.
- Use run_shell for builds and tests when sandbox allows.
- Be concise in chat replies. Put durable notes in files when useful.
- Stop when the task is complete or blocked. Do not invent tool results.
- Never dump large code blocks into chat when file tools are available unless the user asked to see code in chat.`

build_system_prompt :: proc(extra_skills: string = "", tools_reg: ^tools.Registry = nil, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, CODING_AGENT_PREAMBLE)
	strings.write_string(&b, "\n\n")
	mode_sec := mode_prompt_section(mode_from_env(), policy_from_env(), context.temp_allocator)
	strings.write_string(&b, mode_sec)
	auto_sec := autonomy_prompt_section(context.temp_allocator)
	if len(auto_sec) > 0 {
		strings.write_string(&b, "\n\n")
		strings.write_string(&b, auto_sec)
	}
	strings.write_string(&b, "\n\n## Tools\n\n")
	reg := tools_reg
	if reg == nil {
		reg = tools.registry()
	}
	catalog := tools.describe_for_prompt(reg, context.temp_allocator)
	strings.write_string(&b, catalog)
	strings.write_string(&b, "\n\nPrefer native function/tool calling when the API supports it. ")
	strings.write_string(&b, "If the model cannot emit tool_calls, fall back to lines of the form:\n")
	strings.write_string(&b, "TOOL <name> {json args}\n")
	strings.write_string(&b, "You may emit multiple TOOL lines in one reply. After tool results, continue until the task is done.\n")

	agents := load_agents_md(context.temp_allocator)
	if len(agents) > 0 {
		strings.write_string(&b, "\n\n## Project instructions (AGENTS.md)\n\n")
		strings.write_string(&b, agents)
	}

	if len(extra_skills) > 0 {
		strings.write_string(&b, "\n\n## Skills\n\n")
		strings.write_string(&b, extra_skills)
	}
	return strings.to_string(b)
}

load_agents_md :: proc(allocator := context.allocator) -> string {
	roots := make([dynamic]string, context.temp_allocator)
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		append(&roots, st.workspace)
	}
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
		append(&roots, cwd)
	}
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	append(&roots, cfg)

	names := []string{"AGENTS.md", "CLAUDE.md", "nullray.md"}
	for root in roots {
		for name in names {
			path, jerr := filepath.join({root, name}, context.temp_allocator)
			if jerr != nil {
				continue
			}
			data, rerr := os.read_entire_file(path, allocator)
			if rerr == nil && len(data) > 0 {
				if len(data) > constants.MAX_TOOL_FILE_BYTES {
					delete(data)
					continue
				}
				return string(data)
			}
		}
	}
	return ""
}

load_skills_prompt :: proc(allocator := context.allocator) -> string {
	loaded, _ := skills.load_default(allocator)
	if len(loaded) == 0 {
		return ""
	}
	out := skills.render_system_prompt(loaded[:], allocator)
	skills.skills_destroy(&loaded)
	return out
}
