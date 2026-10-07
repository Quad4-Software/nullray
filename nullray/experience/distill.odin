// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
exp_distill: group recent entries by task signature and write a curated
skill-shaped digest to experience.md beside the store. The prompt block
folds its head back in, and the file is plain markdown for /view.
*/

package experience

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "nullray:sandbox"

EXP_DISTILL_GROUPS :: 8
EXP_DISTILL_ENTRY_CHARS :: 220
EXP_DISTILL_TOOLS :: 8

@(private)
Exp_Group :: struct {
	sig:     string,
	task:    string,
	runs:    int,
	fails:   int,
	tools:   [dynamic]string,
	note:    string,
	last_ts: i64,
}

// Build the digest markdown for a set of entries. Testable without files.
exp_distill_digest :: proc(entries: []Exp_Entry, allocator := context.allocator) -> string {
	groups := make([dynamic]Exp_Group, context.temp_allocator)
	for e in entries {
		g: ^Exp_Group
		for &existing in groups {
			if existing.sig == e.sig {
				g = &existing
				break
			}
		}
		if g == nil {
			append(&groups, Exp_Group{
				sig = e.sig,
				task = e.task,
				tools = make([dynamic]string, context.temp_allocator),
			})
			g = &groups[len(groups) - 1]
		}
		g.runs += 1
		if exp_failed(e.outcome) {
			g.fails += 1
		}
		if e.ts >= g.last_ts {
			g.last_ts = e.ts
			g.note = e.note
			if len(e.task) > 0 {
				g.task = e.task
			}
		}
		for name in e.tools {
			if len(g.tools) >= EXP_DISTILL_TOOLS {
				break
			}
			seen := false
			for have in g.tools {
				if have == name {
					seen = true
					break
				}
			}
			if !seen {
				append(&g.tools, name)
			}
		}
	}
	slice.sort_by(groups[:], proc(a, b: Exp_Group) -> bool {
		if a.runs != b.runs {
			return a.runs > b.runs
		}
		return a.last_ts > b.last_ts
	})
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "---\n")
	strings.write_string(&b, "name: experience\n")
	strings.write_string(&b, "description: distilled turn history, what worked and what to avoid\n")
	strings.write_string(&b, "---\n\n")
	strings.write_string(&b, "# Experience digest\n\n")
	shown := 0
	for g in groups {
		if shown >= EXP_DISTILL_GROUPS {
			break
		}
		shown += 1
		seq := strings.join(g.tools[:], "->", context.temp_allocator)
		if len(seq) == 0 {
			seq = "(no tools)"
		}
		line := fmt.aprintf(
			"- task \"%s\" (%d runs, %d failed): %s ; last: %s\n",
			g.task, g.runs, g.fails, seq, g.note,
			allocator = context.temp_allocator,
		)
		if len(line) > EXP_DISTILL_ENTRY_CHARS {
			line = fmt.aprintf("%.*s...\n", EXP_DISTILL_ENTRY_CHARS, line, allocator = context.temp_allocator)
		}
		strings.write_string(&b, line)
	}
	stop_n := 0
	for e in entries {
		if stop_n >= EXP_STOP_LINES {
			break
		}
		if !exp_failed(e.outcome) {
			continue
		}
		m := min(len(e.tools), 3)
		if m < 2 {
			continue
		}
		seq := strings.join(e.tools[len(e.tools) - m:], "->", context.temp_allocator)
		fmt.sbprintf(&b, "- stop: %s repeated before %s\n", seq, e.outcome)
		stop_n += 1
	}
	return strings.to_string(b)
}

// Write the digest to a specific path. Returns err "" on success.
exp_distill_to :: proc(entries: []Exp_Entry, path: string, allocator := context.allocator) -> string {
	body := exp_distill_digest(entries, context.temp_allocator)
	if werr := os.write_entire_file(path, transmute([]u8)body); werr != nil {
		return fmt.aprintf("experience digest write failed: %v", werr, allocator = allocator)
	}
	return ""
}

// Load the store, distill, and write experience.md beside it.
// Returns the written path, or an error message.
exp_distill :: proc(allocator := context.allocator) -> (path: string, err: string) {
	entries := exp_load_entries(context.temp_allocator)
	defer exp_destroy_entries(&entries, context.temp_allocator)
	if len(entries) == 0 {
		return "", strings.clone("no experience entries yet", allocator)
	}
	st := exp_store(context.temp_allocator)
	_ = sandbox.mkdir_all(st.dir)
	out, jerr := filepath.join({st.dir, EXP_DIGEST_FILE}, context.temp_allocator)
	if jerr != nil {
		return "", strings.clone("experience path failed", allocator)
	}
	if werr := exp_distill_to(entries[:], out, allocator); len(werr) > 0 {
		return "", werr
	}
	return strings.clone(out, allocator), ""
}
