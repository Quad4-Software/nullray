// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Prompt tiers, the tiny tool set, and tool-name normalization plus
edit-distance suggestion for weak models that emit name variants.
*/

package tools

import "core:strings"

// Prompt tiers: Full ships every schema, Lean ships the core set plus deferred
// activation, Tiny is the compact profile for small local models.
Prompt_Tier :: enum {
	Full,
	Lean,
	Tiny,
}

// The tool surface a tiny local model can handle: one screen of core verbs.
tiny_core_tool :: proc(name: string) -> bool {
	switch name {
	case "read_file", "write_file", "edit_file", "apply_edits", "list_dir",
		"grep_files", "glob_files", "run_shell", "compact_context", "search_tools",
		"read_artifact", "grep_artifact",
		// Interactive TUI forms and theme control must stay visible on local
		// Tiny tier or models cannot discover show_view / set_tui at all.
		"ask_question", "ask_secret", "show_view", "set_tui",
		"load_skill", "list_skills", "skill_write",
		"canvas_list", "canvas_save", "canvas_open", "show_art",
		"fetch_url", "fetch_rss":
		return true
	}
	return false
}

// Lowercase, collapse - / . separators to _, and drop provider prefixes such as
// "default_api." or "functions." that some models prepend.
normalize_tool_name :: proc(name: string, allocator := context.allocator) -> string {
	s := strings.trim_space(name)
	if i := strings.last_index(s, "."); i >= 0 {
		s = s[i + 1:]
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for c in s {
		switch c {
		case '-', ' ', '/', ':':
			strings.write_byte(&b, '_')
		case:
			strings.write_byte(&b, u8(c))
		}
	}
	return strings.to_lower(strings.to_string(b), allocator)
}

// Nearest registered tool by edit distance for the did-you-mean hint.
closest_tool_name :: proc(r: ^Registry, name: string, allocator := context.allocator) -> string {
	if r == nil {
		return ""
	}
	norm := normalize_tool_name(name, context.temp_allocator)
	best := ""
	best_d := max(int)
	for t in r.tools {
		d := name_edit_distance(norm, t.name, context.temp_allocator)
		if d < best_d {
			best_d = d
			best = t.name
		}
	}
	limit := 2
	if len(norm) / 3 > limit {
		limit = len(norm) / 3
	}
	if best_d <= limit {
		return best
	}
	return ""
}

@(private)
name_edit_distance :: proc(a, b: string, allocator := context.allocator) -> int {
	if a == b {
		return 0
	}
	la, lb := len(a), len(b)
	if la == 0 {
		return lb
	}
	if lb == 0 {
		return la
	}
	prev := make([]int, lb + 1, allocator)
	cur := make([]int, lb + 1, allocator)
	for j := 0; j <= lb; j += 1 {
		prev[j] = j
	}
	for i := 1; i <= la; i += 1 {
		cur[0] = i
		for j := 1; j <= lb; j += 1 {
			cost := 0
			if a[i - 1] != b[j - 1] {
				cost = 1
			}
			cur[j] = min(cur[j - 1] + 1, min(prev[j] + 1, prev[j - 1] + cost))
		}
		prev, cur = cur, prev
	}
	return prev[lb]
}

