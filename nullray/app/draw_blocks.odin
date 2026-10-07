// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Transcript block types and block assembly helpers.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:ui"

Transcript_Block :: struct {
	prefix:       string,
	body:         string,
	prefix_fg:    ui.Color,
	body_fg:      ui.Color,
	prefix_style: ui.Style,
	body_style:   ui.Style,
	row_bg:       ui.Color,
	has_bg:       bool,
	gutter:       bool,
	gap:          bool,
	caret:        bool,
	is_code:      bool,
	lang:         string,
	is_md:        bool,
	is_table:     bool,
	md_table:     ui.Md_Table,
	expand_kind:  string,
	expand_id:    string,
	expand_body:  string,
}

CODE_PREVIEW_LINES :: 16
TOOL_PREVIEW_LINES :: 3
CONTENT_X :: 2

// NULLRAY_COLLAPSE=0 keeps every tool and think block fully expanded.
@(private)
collapse_enabled :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_COLLAPSE, context.temp_allocator)
	if !ok {
		return true
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "false", "off", "no", "disable":
		return false
	}
	return true
}

// Per-block expand state. expand_all flips the default and per-id entries
// act as overrides, so a click under expand_all collapses that block.
@(private)
app_block_expanded :: proc(a: ^App, id: string) -> bool {
	if a == nil {
		return false
	}
	_, toggled := a.expanded[id]
	return a.expand_all != toggled
}

@(private)
app_block_toggle :: proc(a: ^App, id: string) {
	if a.expanded == nil {
		a.expanded = make(map[string]bool)
	}
	if id in a.expanded {
		for k in a.expanded {
			if k == id {
				delete(k)
				break
			}
		}
		delete_key(&a.expanded, id)
		return
	}
	a.expanded[strings.clone(id)] = true
}

// Fold a long body to a marker plus its tail, like opencode's "(N earlier
// lines)" preview. Returns the preview text and whether it collapsed.
@(private)
collapse_preview :: proc(body: string, keep := TOOL_PREVIEW_LINES) -> (string, bool) {
	total := strings.count(body, "\n") + 1
	if total <= keep + 1 {
		return "", false
	}
	// Last `keep` lines: index of the newline that starts that tail.
	start := len(body)
	need := keep
	for i := len(body) - 1; i >= 0 && need > 0; i -= 1 {
		if body[i] == '\n' {
			need -= 1
			if need == 0 {
				start = i + 1
			}
		}
	}
	tail := body[start:]
	return fmt.tprintf("… %d earlier lines\n%s", total - keep, tail), true
}

// Collapse decision for a block identified by id. Returns the body to
// draw plus expand fields: a collapsed block gets a preview and an
// expanded one keeps its toggle so a click folds it back.
@(private)
collapse_apply :: proc(a: ^App, id, body: string) -> (out, kind, eid: string) {
	if !collapse_enabled() || len(id) == 0 {
		return body, "", ""
	}
	if app_block_expanded(a, id) {
		return body, "block", id
	}
	if pv, ok := collapse_preview(body); ok {
		return pv, "block", id
	}
	return body, "", ""
}

@(private)
block_body_width :: proc(buf_width: int, prefix: string) -> int {
	return max(1, buf_width - CONTENT_X - ui.string_cols(prefix) - 1)
}

@(private)
block_height :: proc(block: Transcript_Block, buf_width: int) -> int {
	if block.gap {
		return 1
	}
	bw := block_body_width(buf_width, block.prefix)
	if block.is_code {
		// Keep in sync with app_draw_code_block: inner_w = content_w - 4
		// and the painter uses word_wrap_lines, not char wrapping.
		inner_w := max(1, buf_width - 4)
		lines := len(ui.word_wrap_lines(block.body, inner_w, context.temp_allocator, CODE_PREVIEW_LINES))
		if lines <= 0 {
			lines = 1
		}
		shown := min(lines, CODE_PREVIEW_LINES)
		// header + body + footer
		return 2 + shown
	}
	if block.is_table {
		return max(1, ui.md_table_height(block.md_table, bw))
	}
	if len(block.body) == 0 {
		return 1
	}
	if block.is_md {
		return max(1, ui.md_text_line_count(block.body, bw))
	}
	return max(1, ui.wrap_line_count(block.body, bw))
}

@(private)
app_append_gap :: proc(blocks: ^[dynamic]Transcript_Block) {
	if len(blocks) == 0 {
		return
	}
	last := blocks[len(blocks) - 1]
	if last.gap {
		return
	}
	append(blocks, Transcript_Block{gap = true})
}

// Artifact id after artifact= in a tool result envelope.
@(private)
artifact_id_of :: proc(content: string) -> string {
	idx := strings.index(content, "artifact=")
	if idx < 0 {
		return ""
	}
	rest := content[idx + len("artifact="):]
	end := 0
	for end < len(rest) {
		c := rest[end]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
			end += 1
			continue
		}
		break
	}
	return rest[:end]
}

@(private)
tool_artifact_stub :: proc(content: string, allocator := context.allocator) -> (string, bool) {
	idx := strings.index(content, "artifact=")
	if idx < 0 {
		return "", false
	}
	rest := content[idx + len("artifact="):]
	end := 0
	for end < len(rest) {
		c := rest[end]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
			end += 1
			continue
		}
		break
	}
	if end == 0 {
		return "", false
	}
	id := rest[:end]
	head := content
	nl := strings.index_byte(content, '\n')
	if nl > 0 {
		head = content[:nl]
	}
	if len(head) > 120 {
		head = ui.truncate_utf8_bytes(head, 120)
	}
	return fmt.aprintf("%s (expand: /artifact %s)", head, id, allocator = allocator), true
}
