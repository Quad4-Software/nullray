// SPDX-License-Identifier: 0BSD
/*
MessagePack transcript encode/decode and atomic session writes.
*/

package store

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:provider"

session_path_is_msgpack :: proc(path: string) -> bool {
	return strings.has_suffix(path, ".msgpack")
}

session_path_is_jsonl :: proc(path: string) -> bool {
	return strings.has_suffix(path, ".jsonl")
}

atomic_write_bytes :: proc(path: string, data: []u8) -> bool {
	tmp := fmt.tprintf("%s.tmp.%d", path, os.get_pid())
	if os.write_entire_file(tmp, data) != nil {
		_ = os.remove(tmp)
		return false
	}
	if os.rename(tmp, path) != nil {
		_ = os.remove(path)
		if os.rename(tmp, path) != nil {
			_ = os.remove(tmp)
			return false
		}
	}
	return true
}

save_transcript_msgpack :: proc(path: string, messages: []provider.Message) -> bool {
	ensure_session_dir()
	buf := make([dynamic]u8, 0, 1024, context.temp_allocator)
	count := 0
	for m in messages {
		if m.role != .System {
			count += 1
		}
	}
	mp_write_array_hdr(&buf, count)
	for m in messages {
		if m.role == .System {
			continue
		}
		nkeys := 3
		if len(m.name) > 0 {
			nkeys += 1
		}
		if len(m.tool_call_id) > 0 {
			nkeys += 1
		}
		if len(m.reasoning) > 0 {
			nkeys += 1
		}
		if len(m.tool_calls) > 0 {
			nkeys += 1
		}
		mp_write_map_hdr(&buf, nkeys)
		mp_write_str(&buf, "ts")
		mp_write_i64(&buf, i64(time.to_unix_seconds(time.now())))
		mp_write_str(&buf, "role")
		mp_write_str(&buf, provider.role_string(m.role))
		mp_write_str(&buf, "content")
		mp_write_str(&buf, m.content)
		if len(m.name) > 0 {
			mp_write_str(&buf, "name")
			mp_write_str(&buf, m.name)
		}
		if len(m.tool_call_id) > 0 {
			mp_write_str(&buf, "tool_call_id")
			mp_write_str(&buf, m.tool_call_id)
		}
		if len(m.reasoning) > 0 {
			mp_write_str(&buf, "reasoning")
			mp_write_str(&buf, m.reasoning)
		}
		if len(m.tool_calls) > 0 {
			mp_write_str(&buf, "tool_calls")
			mp_write_array_hdr(&buf, len(m.tool_calls))
			for tc in m.tool_calls {
				mp_write_map_hdr(&buf, 3)
				mp_write_str(&buf, "id")
				mp_write_str(&buf, tc.id)
				mp_write_str(&buf, "name")
				mp_write_str(&buf, tc.name)
				mp_write_str(&buf, "arguments")
				mp_write_str(&buf, tc.arguments)
			}
		}
	}
	return atomic_write_bytes(path, buf[:])
}

load_transcript_msgpack :: proc(path: string, allocator := context.allocator) -> (msgs: [dynamic]provider.Message, ok: bool) {
	msgs = make([dynamic]provider.Message, allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return msgs, false
	}
	r := Mp_Reader{data = data}
	n, nok := mp_read_array_len(&r)
	if !nok {
		return msgs, false
	}
	for _ in 0 ..< n {
		nk, mok := mp_read_map_len(&r)
		if !mok {
			return msgs, false
		}
		role_s := ""
		content := ""
		name := ""
		reasoning := ""
		tool_call_id := ""
		calls: []provider.Tool_Call
		for _ in 0 ..< nk {
			key, kok := mp_read_str(&r)
			if !kok {
				return msgs, false
			}
			switch key {
			case "role":
				role_s, kok = mp_read_str(&r)
				if !kok {
					return msgs, false
				}
			case "content":
				content, kok = mp_read_str(&r)
				if !kok {
					return msgs, false
				}
			case "name":
				name, kok = mp_read_str(&r)
				if !kok {
					return msgs, false
				}
			case "reasoning":
				reasoning, kok = mp_read_str(&r)
				if !kok {
					return msgs, false
				}
			case "tool_call_id":
				tool_call_id, kok = mp_read_str(&r)
				if !kok {
					return msgs, false
				}
			case "ts":
				_, kok = mp_read_i64(&r)
				if !kok {
					return msgs, false
				}
			case "tool_calls":
				cn, cok := mp_read_array_len(&r)
				if !cok {
					return msgs, false
				}
				calls = make([]provider.Tool_Call, cn, allocator)
				for i in 0 ..< cn {
					tn, tok := mp_read_map_len(&r)
					if !tok {
						return msgs, false
					}
					id, nm, args := "", "", ""
					for _ in 0 ..< tn {
						k2, k2ok := mp_read_str(&r)
						if !k2ok {
							return msgs, false
						}
						v2, v2ok := mp_read_str(&r)
						if !v2ok {
							return msgs, false
						}
						switch k2 {
						case "id":
							id = v2
						case "name":
							nm = v2
						case "arguments":
							args = v2
						}
					}
					calls[i] = provider.Tool_Call{
						id = strings.clone(id, allocator),
						name = strings.clone(nm, allocator),
						arguments = strings.clone(args, allocator),
					}
				}
			case:
				if !mp_skip_value(&r) {
					return msgs, false
				}
			}
		}
		role := provider.Role.User
		switch role_s {
		case "assistant":
			role = .Assistant
		case "system":
			continue
		case "tool":
			role = .Tool
		case "user":
			role = .User
		case:
			continue
		}
		if len(content) > constants.MAX_MESSAGE_CHARS {
			content = content[:constants.MAX_MESSAGE_CHARS]
		}
		msg := provider.Message{
			role = role,
			content = strings.clone(content, allocator),
		}
		if len(name) > 0 {
			msg.name = strings.clone(name, allocator)
		}
		if len(reasoning) > 0 {
			msg.reasoning = strings.clone(reasoning, allocator)
		}
		if len(tool_call_id) > 0 {
			msg.tool_call_id = strings.clone(tool_call_id, allocator)
		}
		if len(calls) > 0 {
			msg.tool_calls = calls
		}
		append(&msgs, msg)
	}
	return msgs, true
}

export_transcript_jsonl :: proc(src_path, dest_jsonl: string) -> bool {
	msgs, ok := load_transcript(src_path)
	if !ok {
		return false
	}
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	return save_transcript_jsonl(dest_jsonl, msgs[:])
}
