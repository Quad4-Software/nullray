// SPDX-License-Identifier: 0BSD
/*
Enforced path leases so parallel agents do not clobber writes.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"

Lease :: struct {
	agent_id:   string,
	path:       string,
	reason:     string,
	expires_at: i64,
	heartbeat:  i64,
}

Lease_Board :: struct {
	mu:     sync.Mutex,
	leases: map[string]Lease,
	dir:    string,
}

lease_board_init :: proc(b: ^Lease_Board) {
	b^ = {}
	b.leases = make(map[string]Lease)
	ws := workspace_dir()
	b.dir, _ = filepath.join({ws, constants.LEASES_DIR})
	_ = os.make_directory_all(b.dir)
}

lease_board_destroy :: proc(b: ^Lease_Board) {
	if b == nil {
		return
	}
	sync.mutex_lock(&b.mu)
	for k, &l in b.leases {
		delete(l.agent_id)
		delete(l.path)
		delete(l.reason)
		delete(k)
	}
	delete(b.leases)
	delete(b.dir)
	sync.mutex_unlock(&b.mu)
	b^ = {}
}

normalize_lease_path :: proc(path: string, allocator := context.allocator) -> string {
	clean, _ := filepath.clean(path, context.temp_allocator)
	return strings.clone(clean, allocator)
}

lease_expired :: proc(l: Lease, now: i64) -> bool {
	return l.expires_at > 0 && now > l.expires_at
}

lease_acquire :: proc(
	b: ^Lease_Board,
	agent_id: string,
	path: string,
	reason: string,
	allocator := context.allocator,
) -> (err: string) {
	if b == nil {
		return ""
	}
	if len(agent_id) == 0 || agent_id == "main" {
		// Main agent still takes leases when children may be active.
	}
	np := normalize_lease_path(path, context.temp_allocator)
	now := time.time_to_unix(time.now())
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	if old, ok := b.leases[np]; ok {
		if !lease_expired(old, now) && old.agent_id != agent_id {
			return fmt.aprintf(
				"path leased by %s until %d: %s (%s)",
				old.agent_id,
				old.expires_at,
				old.path,
				old.reason,
				allocator = allocator,
			)
		}
		delete(old.agent_id)
		delete(old.path)
		delete(old.reason)
		map_key := ""
		for mk in b.leases {
			if mk == np {
				map_key = mk
				break
			}
		}
		if len(map_key) > 0 {
			delete_key(&b.leases, map_key)
			delete(map_key)
		}
	}
	key := strings.clone(np)
	l := Lease{
		agent_id = strings.clone(agent_id),
		path = strings.clone(np),
		reason = strings.clone(reason),
		expires_at = now + i64(constants.LEASE_TTL_SEC),
		heartbeat = now,
	}
	b.leases[key] = l
	_ = lease_write_file(b, l)
	return ""
}

lease_write_file :: proc(b: ^Lease_Board, l: Lease) -> bool {
	if len(b.dir) == 0 {
		return false
	}
	safe, _ := strings.replace_all(l.path, "/", "_", context.temp_allocator)
	safe, _ = strings.replace_all(safe, "\\", "_", context.temp_allocator)
	if len(safe) > 180 {
		safe = safe[len(safe) - 180:]
	}
	path, _ := filepath.join({b.dir, fmt.tprintf("%s.json", safe)}, context.temp_allocator)
	body := fmt.tprintf(
		`{{"agent_id":%q,"path":%q,"reason":%q,"expires_at":%d,"heartbeat":%d}}`+"\n",
		l.agent_id,
		l.path,
		l.reason,
		l.expires_at,
		l.heartbeat,
	)
	return os.write_entire_file(path, transmute([]byte)body) == nil
}

lease_heartbeat :: proc(b: ^Lease_Board, agent_id: string) {
	if b == nil {
		return
	}
	now := time.time_to_unix(time.now())
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	for _, &l in b.leases {
		if l.agent_id == agent_id {
			l.heartbeat = now
			l.expires_at = now + i64(constants.LEASE_TTL_SEC)
		}
	}
}

lease_release_agent :: proc(b: ^Lease_Board, agent_id: string) {
	if b == nil {
		return
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	to_del := make([dynamic]string, context.temp_allocator)
	for k, l in b.leases {
		if l.agent_id == agent_id {
			append(&to_del, k)
		}
	}
	for k in to_del {
		if l, ok := b.leases[k]; ok {
			delete(l.agent_id)
			delete(l.path)
			delete(l.reason)
		}
		delete_key(&b.leases, k)
		delete(k)
	}
}

lease_release_path :: proc(b: ^Lease_Board, agent_id: string, path: string) {
	if b == nil {
		return
	}
	np := normalize_lease_path(path, context.temp_allocator)
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	if l, ok := b.leases[np]; ok {
		if l.agent_id == agent_id {
			delete(l.agent_id)
			delete(l.path)
			delete(l.reason)
			delete_key(&b.leases, np)
		}
	}
}

lease_check_write :: proc(b: ^Lease_Board, agent_id: string, path: string, allocator := context.allocator) -> string {
	if b == nil {
		return ""
	}
	np := normalize_lease_path(path, context.temp_allocator)
	now := time.time_to_unix(time.now())
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	if l, ok := b.leases[np]; ok {
		if lease_expired(l, now) {
			return ""
		}
		if l.agent_id != agent_id {
			return fmt.aprintf(
				"write blocked: leased by %s (%s) until %d",
				l.agent_id,
				l.reason,
				l.expires_at,
				allocator = allocator,
			)
		}
	}
	return ""
}

lease_status_text :: proc(b: ^Lease_Board, allocator := context.allocator) -> string {
	if b == nil {
		return strings.clone("(no leases)", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	bldr: strings.Builder
	strings.builder_init(&bldr, allocator)
	if len(b.leases) == 0 {
		strings.write_string(&bldr, "(no leases)")
		return strings.to_string(bldr)
	}
	for _, l in b.leases {
		fmt.sbprintf(&bldr, "%s -> %s (%s)\n", l.path, l.agent_id, l.reason)
	}
	return strings.to_string(bldr)
}

GIT_INDEX_LEASE :: "@git/index"

command_needs_git_index_lease :: proc(command: string) -> bool {
	low := strings.to_lower(command, context.temp_allocator)
	if !strings.contains(low, "git ") && !strings.has_prefix(strings.trim_space(low), "git") {
		return false
	}
	return strings.contains(low, " add") ||
		strings.contains(low, " commit") ||
		strings.contains(low, " rebase") ||
		strings.contains(low, " checkout") ||
		strings.contains(low, " merge") ||
		strings.contains(low, " stash") ||
		strings.contains(low, " reset")
}

command_is_git_stash :: proc(command: string) -> bool {
	low := strings.to_lower(command, context.temp_allocator)
	return strings.contains(low, "git stash")
}
