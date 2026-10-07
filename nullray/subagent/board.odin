// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Shared task board for spawn groups (phase 3 teams).
Items persist to .nullray/board/items.jsonl. Lines written by older
builds lack the group/blocked_on/result keys and load with empty fields.
*/

package subagent

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Board_Item_Status :: enum {
	Open,
	Claimed,
	Done,
}

Board_Item :: struct {
	id:         string,
	title:      string,
	assignee:   string,
	status:     Board_Item_Status,
	updated_at: i64,
	group:      string,
	blocked_on: [dynamic]string,
	result:     string,
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
	_ = sandbox.mkdir_all(b.dir)
	board_load(b)
}

board_destroy :: proc(b: ^Task_Board) {
	if b == nil {
		return
	}
	sync.mutex_lock(&b.mu)
	for &it in b.items {
		board_item_clear(&it)
	}
	delete(b.items)
	delete(b.dir)
	sync.mutex_unlock(&b.mu)
	b^ = {}
}

board_item_clear :: proc(it: ^Board_Item) {
	delete(it.id)
	delete(it.title)
	delete(it.assignee)
	delete(it.group)
	for d in it.blocked_on {
		delete(d)
	}
	delete(it.blocked_on)
	delete(it.result)
}

board_add :: proc(
	b: ^Task_Board,
	title: string,
	blocked_on: []string = nil,
	group: string = "",
	allocator := context.allocator,
) -> (id: string, err: string) {
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
		group = strings.clone(group),
		blocked_on = make([dynamic]string),
	})
	it := &b.items[len(b.items) - 1]
	for dep in blocked_on {
		d := strings.trim_space(dep)
		if len(d) == 0 {
			continue
		}
		append(&it.blocked_on, strings.clone(d))
	}
	_ = board_save(b)
	return id, ""
}

// Ids in it.blocked_on that are missing or not done. Caller holds b.mu.
board_unmet_deps :: proc(b: ^Task_Board, it: Board_Item, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	for dep in it.blocked_on {
		done := false
		for &o in b.items {
			if o.id == dep {
				done = o.status == .Done
				break
			}
		}
		if !done {
			append(&out, dep)
		}
	}
	return out[:]
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
			pending := board_unmet_deps(b, it, context.temp_allocator)
			if len(pending) > 0 {
				joined := strings.join(pending, ",", context.temp_allocator)
				return fmt.aprintf("blocked: deps not done: %s", joined, allocator = allocator)
			}
			delete(it.assignee)
			it.assignee = strings.clone(agent_id)
			it.status = .Claimed
			it.updated_at = time.time_to_unix(time.now())
			_ = board_save(b)
			return ""
		}
	}
	return fmt.aprintf("unknown board item: %s", id, allocator = allocator)
}

board_done :: proc(
	b: ^Task_Board,
	id: string,
	agent_id: string,
	result: string = "",
	allocator := context.allocator,
) -> string {
	if b == nil {
		return strings.clone("no board", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	for &it in b.items {
		if it.id == id {
			it.status = .Done
			it.updated_at = time.time_to_unix(time.now())
			delete(it.result)
			it.result = strings.clone(result)
			_ = board_save(b)
			return ""
		}
	}
	return fmt.aprintf("unknown board item: %s", id, allocator = allocator)
}

// group filters items: empty shows all, a set group shows that group plus
// unscoped items so group-less tasks stay visible to every caller.
board_list_text :: proc(b: ^Task_Board, group: string = "", allocator := context.allocator) -> string {
	if b == nil {
		return strings.clone("(no board)", allocator)
	}
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	bld: strings.Builder
	strings.builder_init(&bld, allocator)
	shown := 0
	for it in b.items {
		if len(group) > 0 && len(it.group) > 0 && it.group != group {
			continue
		}
		shown += 1
		st := board_status_string(it.status)
		fmt.sbprintf(&bld, "%s [%s] %s", it.id, st, it.title)
		if len(it.group) > 0 {
			fmt.sbprintf(&bld, " group=%s", it.group)
		}
		if len(it.assignee) > 0 {
			fmt.sbprintf(&bld, " @%s", it.assignee)
		}
		if len(it.blocked_on) > 0 {
			joined := strings.join(it.blocked_on[:], ",", context.temp_allocator)
			fmt.sbprintf(&bld, " deps=%s", joined)
			pending := board_unmet_deps(b, it, context.temp_allocator)
			if len(pending) > 0 {
				fmt.sbprintf(&bld, " blocked-by=%s", strings.join(pending, ",", context.temp_allocator))
			}
		}
		if len(it.result) > 0 {
			line := it.result
			if idx := strings.index_byte(line, '\n'); idx >= 0 {
				line = line[:idx]
			}
			fmt.sbprintf(&bld, " => %s", line)
		}
		strings.write_byte(&bld, '\n')
	}
	if shown == 0 {
		strings.write_string(&bld, "(empty board)")
	}
	return strings.to_string(bld)
}

board_status_string :: proc(s: Board_Item_Status) -> string {
	switch s {
	case .Open:
		return "open"
	case .Claimed:
		return "claimed"
	case .Done:
		return "done"
	}
	return "open"
}

board_status_from_string :: proc(s: string) -> Board_Item_Status {
	switch s {
	case "claimed":
		return .Claimed
	case "done":
		return .Done
	}
	return .Open
}

// Caller holds b.mu. Rewrites items.jsonl, skipped for ephemeral sessions.
board_save :: proc(b: ^Task_Board) -> bool {
	if len(b.dir) == 0 || knowledge_ephemeral() {
		return false
	}
	path, _ := filepath.join({b.dir, "items.jsonl"}, context.temp_allocator)
	bl: strings.Builder
	strings.builder_init(&bl, context.temp_allocator)
	for it in b.items {
		deps: strings.Builder
		strings.builder_init(&deps, context.temp_allocator)
		for dep, i in it.blocked_on {
			if i > 0 {
				strings.write_byte(&deps, ',')
			}
			fmt.sbprintf(&deps, "%q", dep)
		}
		fmt.sbprintf(
			&bl,
			`{{"id":%q,"title":%q,"assignee":%q,"status":%q,"updated":%d,"group":%q,"blocked_on":[%s],"result":%q}}` + "\n",
			it.id,
			it.title,
			it.assignee,
			board_status_string(it.status),
			it.updated_at,
			it.group,
			strings.to_string(deps),
			it.result,
		)
	}
	body := strings.to_string(bl)
	return os.write_entire_file(path, transmute([]byte)body) == nil
}

board_load :: proc(b: ^Task_Board) {
	if len(b.dir) == 0 {
		return
	}
	path, _ := filepath.join({b.dir, "items.jsonl"}, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(line)) == 0 {
			continue
		}
		doc, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
		if perr != nil {
			continue
		}
		obj, ok := doc.(json.Object)
		if !ok {
			continue
		}
		id_raw, id_ok := obj["id"]
		id_s, id_str := id_raw.(json.String)
		if !id_ok || !id_str || len(b.items) >= constants.MAX_BOARD_ITEMS {
			continue
		}
		it := Board_Item{
			id = strings.clone(string(id_s)),
			status = .Open,
			blocked_on = make([dynamic]string),
		}
		if v, found := obj["title"]; found {
			if s, sok := v.(json.String); sok {
				it.title = strings.clone(string(s))
			}
		}
		if v, found := obj["assignee"]; found {
			if s, sok := v.(json.String); sok {
				it.assignee = strings.clone(string(s))
			}
		}
		if v, found := obj["status"]; found {
			if s, sok := v.(json.String); sok {
				it.status = board_status_from_string(string(s))
			}
		}
		if v, found := obj["updated"]; found {
			#partial switch n in v {
			case json.Integer:
				it.updated_at = i64(n)
			case json.Float:
				it.updated_at = i64(n)
			}
		}
		if v, found := obj["group"]; found {
			if s, sok := v.(json.String); sok {
				it.group = strings.clone(string(s))
			}
		}
		if v, found := obj["result"]; found {
			if s, sok := v.(json.String); sok {
				it.result = strings.clone(string(s))
			}
		}
		if v, found := obj["blocked_on"]; found {
			#partial switch bv in v {
			case json.Array:
				for e in bv {
					if s, sok := e.(json.String); sok {
						d := strings.trim_space(string(s))
						if len(d) > 0 {
							append(&it.blocked_on, strings.clone(d))
						}
					}
				}
			case json.String:
				for p in strings.split(string(bv), ",", context.temp_allocator) {
					d := strings.trim_space(p)
					if len(d) > 0 {
						append(&it.blocked_on, strings.clone(d))
					}
				}
			}
		}
		append(&b.items, it)
		idstr := string(id_s)
		if strings.has_prefix(idstr, "t") {
			if n, nok := strconv.parse_int(idstr[1:]); nok && n > b.seq {
				b.seq = n
			}
		}
	}
}
