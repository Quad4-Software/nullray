// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Drop a malformed tool-call turn and resample with a correction note.
Keeping the broken attempt in context raises later error rates.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:provider"

turn_inject_steer :: proc(msgs: ^[dynamic]provider.Message, cfg: Config, allocator := context.allocator) {
	if cfg.poll_steer == nil || msgs == nil {
		return
	}
	note := cfg.poll_steer(cfg.user)
	if len(note) == 0 {
		return
	}
	append(msgs, provider.Message{role = .User, content = note})
	emit(cfg, .Status, "steer: injected")
}

turn_discard_chat_extras :: proc(res: ^provider.Chat_Response, calls: []provider.Tool_Call, text_calls: bool) {
	if res == nil {
		return
	}
	delete(res.model)
	delete(res.err)
	delete(res.finish_reason)
	res.model = ""
	res.err = ""
	res.finish_reason = ""
	if text_calls {
		provider.destroy_tool_calls_owned(calls)
	} else {
		provider.destroy_tool_calls_owned(res.tool_calls)
		res.tool_calls = {}
	}
}

turn_drop_last_attempt :: proc(msgs: ^[dynamic]provider.Message) {
	if msgs == nil || len(msgs) == 0 {
		return
	}
	for len(msgs) > 0 && msgs[len(msgs) - 1].role == .Tool {
		provider.destroy_message(msgs[len(msgs) - 1])
		pop(msgs)
	}
	if len(msgs) > 0 && msgs[len(msgs) - 1].role == .Assistant {
		provider.destroy_message(msgs[len(msgs) - 1])
		pop(msgs)
	}
}

malformed_restart_note :: proc(kind: Malformed_Kind, err: string, retry_left: bool, allocator := context.allocator) -> string {
	if retry_left {
		return fmt.aprintf(
			"The previous assistant tool call was dropped because it was malformed (%s): %s. Do not repeat that call. Emit a valid tool call with corrected JSON, or answer without tools.",
			malformed_kind_name(kind),
			err,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"The previous assistant tool call was dropped because it was malformed (%s): %s. Retry budget exhausted. Answer without further tool calls.",
		malformed_kind_name(kind),
		err,
		allocator = allocator,
	)
}

turn_restart_malformed :: proc(
	msgs: ^[dynamic]provider.Message,
	kind: Malformed_Kind,
	err: string,
	retry_left: bool,
	allocator := context.allocator,
) {
	turn_drop_last_attempt(msgs)
	note := malformed_restart_note(kind, err, retry_left, allocator)
	append(msgs, provider.Message{role = .User, content = note})
}
