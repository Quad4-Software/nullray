// SPDX-License-Identifier: 0BSD
/*
Shared task board for spawn groups (phase 3 teams).
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"

Board_Item_Status :: enum {
	Open,
	Claimed,
	Done,
}

Board_Item :: struct {
	id:          string,
	title:       string,
	assignee:    string,
	status:      Board_Item_Status,
	updated_at:  i64,
}

Task_Board :: struct {
	mu:    sync.Mutex,
	items: [dynamic]Board_Item,
	seq:   int,
	dir:   string,
}

board_init :: proc(b: ^Task_Board) {
	b^ = {}
	b.items = make([dynamic]Board_Item)
	ws := workspace_dir()
	b.dir, _ = filepath.join({ws, constants.BOARD_DIR})
	_ = os.make_directory_all(b.dir)
}

board_destroy :: proc(b: ^Task_Board) {
	if b == nil {
		return
	}
	sync.mutex_lock(&b.mu)
	for &it in b.items {
		delete(it.id)
		delete(it.title)
		delete(it.assignee)
	}
	delete(b.items)
	delete(b.dir)
	sync.mutex_unlock(&b.mu)
	b^ = {}
}

board_add :: proc(b: ^Task_Board, title: string, allocator := context.allocator) -> (id: string, err: string) {
	if b == nil {
		return "", strings.clone("no board", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	if len(b.items) >= constants.MAX_BOARD_ITEMS {
		return "", strings.clone("board full", allocator)
	}
	b.seq += 1
	id = fmt.aprintf("t%d", b.seq, allocator = allocator)
	append(&b.items, Board_Item{
		id = strings.clone(id),
		title = strings.clone(title),
		assignee = strings.clone(""),
		status = .Open,
		updated_at = time.time_to_unix(time.now()),
	})
	return id, ""
}

board_claim :: proc(b: ^Task_Board, id: string, agent_id: string, allocator := context.allocator) -> string {
	if b == nil {
		return strings.clone("no board", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	for &it in b.items {
		if it.id == id {
			if it.status == .Claimed && it.assignee != agent_id {
				return fmt.aprintf("claimed by %s", it.assignee, allocator = allocator)
			}
			delete(it.assignee)
			it.assignee = strings.clone(agent_id)
			it.status = .Claimed
			it.updated_at = time.time_to_unix(time.now())
			return ""
		}
	}
	return fmt.aprintf("unknown board item: %s", id, allocator = allocator)
}

board_done :: proc(b: ^Task_Board, id: string, agent_id: string, allocator := context.allocator) -> string {
	if b == nil {
		return strings.clone("no board", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	for &it in b.items {
		if it.id == id {
			it.status = .Done
			it.updated_at = time.time_to_unix(time.now())
			return ""
		}
	}
	return fmt.aprintf("unknown board item: %s", id, allocator = allocator)
}

board_list_text :: proc(b: ^Task_Board, allocator := context.allocator) -> string {
	if b == nil {
		return strings.clone("(no board)", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	bld: strings.Builder
	strings.builder_init(&bld, allocator)
	if len(b.items) == 0 {
		strings.write_string(&bld, "(empty board)")
		return strings.to_string(bld)
	}
	for it in b.items {
		st := "open"
		switch it.status {
		case .Open:
			st = "open"
		case .Claimed:
			st = "claimed"
		case .Done:
			st = "done"
		}
		fmt.sbprintf(&bld, "%s [%s] %s", it.id, st, it.title)
		if len(it.assignee) > 0 {
			fmt.sbprintf(&bld, " @%s", it.assignee)
		}
		strings.write_byte(&bld, '\n')
	}
	return strings.to_string(bld)
}
