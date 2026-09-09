// SPDX-License-Identifier: 0BSD
/*
Transcript layout cache and view-auto env.
*/

package app

import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:ui"

Layout_Cache :: struct {
	valid:          bool,
	msg_count:      int,
	last_role:      int,
	last_len:       int,
	stream_len:     int,
	think_len:      int,
	live_tool:      string,
	width:          int,
	theme_accent:   ui.Color,
	frozen_heights: [dynamic]int,
	frozen_count:   int,
}

view_auto_from_env :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_VIEW_AUTO, context.temp_allocator)
	if !ok {
		return true
	}
	s := strings.to_lower(strings.trim_space(v), context.temp_allocator)
	switch s {
	case "0", "false", "off", "no", "disable":
		return false
	}
	return true
}

app_layout_cache_clear :: proc(a: ^App) {
	delete(a.layout_cache.frozen_heights)
	delete(a.layout_cache.live_tool)
	a.layout_cache = {}
}

@(private)
layout_cache_key_match :: proc(a: ^App, width: int, accent: ui.Color) -> bool {
	c := a.layout_cache
	if !c.valid {
		return false
	}
	if c.width != width || c.theme_accent != accent {
		return false
	}
	msgs := a.session.messages
	if c.msg_count != len(msgs) {
		return false
	}
	if len(msgs) > 0 {
		last := msgs[len(msgs) - 1]
		if c.last_role != int(last.role) || c.last_len != len(last.content) {
			return false
		}
	}
	return true
}

@(private)
layout_cache_store_frozen :: proc(a: ^App, heights: []int, frozen_n: int, width: int, accent: ui.Color) {
	delete(a.layout_cache.frozen_heights)
	delete(a.layout_cache.live_tool)
	n := min(frozen_n, len(heights))
	a.layout_cache.frozen_heights = make([dynamic]int, n)
	for i in 0 ..< n {
		a.layout_cache.frozen_heights[i] = heights[i]
	}
	a.layout_cache.frozen_count = n
	a.layout_cache.msg_count = len(a.session.messages)
	if len(a.session.messages) > 0 {
		last := a.session.messages[len(a.session.messages) - 1]
		a.layout_cache.last_role = int(last.role)
		a.layout_cache.last_len = len(last.content)
	} else {
		a.layout_cache.last_role = 0
		a.layout_cache.last_len = 0
	}
	a.layout_cache.stream_len = strings.builder_len(a.session.streaming)
	a.layout_cache.think_len = strings.builder_len(a.session.thinking)
	a.layout_cache.live_tool = strings.clone(a.session.live_tool)
	a.layout_cache.width = width
	a.layout_cache.theme_accent = accent
	a.layout_cache.valid = true
}

@(private)
layout_frozen_count :: proc(a: ^App, blocks: []Transcript_Block) -> int {
	n := len(blocks)
	if a.session.has_thinking || a.session.has_streaming || a.session.busy || len(a.session.live_tool) > 0 {
		// Live tail is the last contiguous non-message paint group. Count trailing live-ish blocks.
		live := 0
		if a.session.has_thinking {
			live += 1
		}
		if len(a.session.live_tool) > 0 {
			live += 1
		}
		if a.session.has_streaming || (a.session.busy && len(a.session.live_tool) == 0) {
			live += 1
		}
		// Plus the gap before live section when present.
		if live > 0 && n > live {
			live += 1
		}
		return max(0, n - live)
	}
	return n
}
