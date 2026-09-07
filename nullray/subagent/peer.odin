// SPDX-License-Identifier: 0BSD
/*
Optional peer messaging when NULLRAY_SUBAGENT_TEAMS is on.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"

Peer_Message :: struct {
	from:      string,
	to:        string,
	body:      string,
	created:   i64,
	read:      bool,
}

Peer_Inbox :: struct {
	mu:   sync.Mutex,
	msgs: [dynamic]Peer_Message,
}

peer_inbox_init :: proc(p: ^Peer_Inbox) {
	p^ = {}
	p.msgs = make([dynamic]Peer_Message)
}

peer_inbox_destroy :: proc(p: ^Peer_Inbox) {
	if p == nil {
		return
	}
	sync.mutex_lock(&p.mu)
	for &m in p.msgs {
		delete(m.from)
		delete(m.to)
		delete(m.body)
	}
	delete(p.msgs)
	sync.mutex_unlock(&p.mu)
	p^ = {}
}

peer_send :: proc(
	p: ^Peer_Inbox,
	from: string,
	to: string,
	body: string,
	allocator := context.allocator,
) -> string {
	if p == nil {
		return strings.clone("no inbox", allocator)
	}
	if !teams_enabled_from_env() {
		return strings.clone("peer messaging disabled (set NULLRAY_SUBAGENT_TEAMS=1)", allocator)
	}
	trimmed := strings.trim_space(body)
	if len(trimmed) == 0 {
		return strings.clone("empty message", allocator)
	}
	if len(trimmed) > constants.MAX_PEER_MESSAGE_CHARS {
		trimmed = trimmed[:constants.MAX_PEER_MESSAGE_CHARS]
	}
	sync.mutex_lock(&p.mu)
	defer sync.mutex_unlock(&p.mu)
	append(&p.msgs, Peer_Message{
		from = strings.clone(from),
		to = strings.clone(to),
		body = strings.clone(trimmed),
		created = time.time_to_unix(time.now()),
	})
	return ""
}

peer_read :: proc(p: ^Peer_Inbox, agent_id: string, allocator := context.allocator) -> string {
	if p == nil {
		return strings.clone("(no inbox)", allocator)
	}
	sync.mutex_lock(&p.mu)
	defer sync.mutex_unlock(&p.mu)
	bld: strings.Builder
	strings.builder_init(&bld, allocator)
	n := 0
	for &m in p.msgs {
		if m.to == agent_id || m.to == "*" {
			fmt.sbprintf(&bld, "from=%s: %s\n", m.from, m.body)
			m.read = true
			n += 1
		}
	}
	if n == 0 {
		strings.write_string(&bld, "(no messages)")
	}
	return strings.to_string(bld)
}
