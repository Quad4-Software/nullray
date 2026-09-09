// SPDX-License-Identifier: 0BSD
/*
CLI session inspect summary and follow tail.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:provider"
import "nullray:store"

resolve_inspect_path :: proc(name: string, allocator := context.allocator) -> string {
	trimmed := strings.trim_space(name)
	if len(trimmed) == 0 || trimmed == "." {
		return store.default_session_path(allocator)
	}
	if store.looks_like_session_path(trimmed) {
		return strings.clone(trimmed, allocator)
	}
	return store.named_session_path(trimmed, allocator)
}

transcript_line_count :: proc(path: string) -> int {
	if store.session_path_is_msgpack(path) {
		msgs, ok := store.load_transcript(path, context.temp_allocator)
		if !ok {
			return 0
		}
		n := len(msgs)
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
		return n
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return 0
	}
	n := 0
	for raw in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(raw)) > 0 {
			n += 1
		}
	}
	return n
}

session_inspect_text :: proc(path: string, allocator := context.allocator) -> string {
	stem := filepath.base(path)
	name := stem
	if strings.has_suffix(stem, ".jsonl") {
		name = stem[:len(stem) - len(".jsonl")]
	} else if strings.has_suffix(stem, ".msgpack") {
		name = stem[:len(stem) - len(".msgpack")]
	}
	meta, has_meta := store.load_session_meta(path, context.temp_allocator)
	preview := store.session_preview(path, context.temp_allocator)
	count := transcript_line_count(path)
	group := meta.group
	if len(group) == 0 {
		group = "(none)"
	}
	provider_id := meta.provider
	if len(provider_id) == 0 {
		provider_id = "(none)"
	}
	model := meta.model
	if len(model) == 0 {
		model = "(none)"
	}
	mode := meta.mode
	if len(mode) == 0 {
		mode = "(none)"
	}
	exists := os.exists(path)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "name: %s\n", name)
	fmt.sbprintf(&b, "path: %s\n", path)
	fmt.sbprintf(&b, "exists: %v\n", exists)
	fmt.sbprintf(&b, "messages: %d\n", count)
	if has_meta {
		fmt.sbprintf(&b, "provider: %s\n", provider_id)
		fmt.sbprintf(&b, "model: %s\n", model)
		fmt.sbprintf(&b, "group: %s\n", group)
		fmt.sbprintf(&b, "mode: %s\n", mode)
		fmt.sbprintf(&b, "turns: %d\n", meta.turns)
		fmt.sbprintf(&b, "tokens: %d\n", meta.total_tokens)
	}
	fmt.sbprintf(&b, "preview: %s\n", preview)
	return strings.to_string(b)
}

session_inspect_follow :: proc(path: string) -> int {
	if !os.exists(path) {
		fmt.eprintln("nullray: session not found:", path)
		return 1
	}
	text := session_inspect_text(path, context.temp_allocator)
	fmt.println(text)
	if store.session_path_is_msgpack(path) {
		last_size: i64 = 0
		if st, err := os.stat(path, context.temp_allocator); err == nil {
			last_size = st.size
		}
		for {
			st, err := os.stat(path, context.temp_allocator)
			if err != nil {
				time.sleep(500 * time.Millisecond)
				continue
			}
			if st.size != last_size {
				last_size = st.size
				fmt.println("---")
				fmt.println(session_inspect_text(path, context.temp_allocator))
			}
			time.sleep(time.Duration(constants.POLL_TIMEOUT_MS) * time.Millisecond)
		}
	}
	offset: i64 = 0
	if st, err := os.stat(path, context.temp_allocator); err == nil {
		offset = st.size
	}
	for {
		st, err := os.stat(path, context.temp_allocator)
		if err != nil {
			time.sleep(500 * time.Millisecond)
			continue
		}
		if st.size > offset {
			f, oerr := os.open(path, {.Read})
			if oerr == nil {
				defer os.close(f)
				_, _ = os.seek(f, offset, .Start)
				buf: [8192]u8
				for {
					n, rerr := os.read(f, buf[:])
					if n > 0 {
						fmt.print(string(buf[:n]))
					}
					if rerr != nil || n == 0 {
						break
					}
				}
				offset = st.size
			}
		}
		time.sleep(time.Duration(constants.POLL_TIMEOUT_MS) * time.Millisecond)
	}
	return 0
}
