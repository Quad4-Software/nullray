// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Standing-watch tool. watch_checkpoint is the delta gate a watch prompt
calls once per run: it persists the seen id set under
.nullray/watch/<id>/, reports only the new items, and fires a desktop
notification on hits so daemon turns surface without a client poll.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:notify"
import "nullray:schedule"

register_watch_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "watch_checkpoint",
		description = "Standing-watch delta gate. Pass this run's stable item ids (CVE ids, URLs, titles) plus an optional note. Returns the new-item count and persists state under .nullray/watch/<id>. Only summarize to the user when new items exist",
		schema_json = `{"type":"object","properties":{"id":{"type":"string","description":"watch id from the scheduled prompt"},"items":{"type":"array","items":{"type":"string"},"description":"stable ids for current findings"},"note":{"type":"string","description":"one-line run summary"}},"required":["id","items"]}`,
		kind = .Read,
		run = tool_watch_checkpoint,
	})
}

tool_watch_checkpoint :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	doc, perr := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return "", fmt.aprintf("bad tool args JSON: %v", perr, allocator = allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return "", strings.clone("tool args must be a JSON object", allocator)
	}
	id := 0
	switch v in obj["id"] {
	case json.Integer:
		id = int(v)
	case json.Float:
		id = int(v)
	case json.String:
		n, n_ok := strconv.parse_int(strings.trim_space(string(v)))
		if !n_ok {
			return "", strings.clone("id must be a number", allocator)
		}
		id = n
	case json.Object, json.Array, json.Boolean, json.Null:
	}
	if id <= 0 {
		return "", strings.clone("id required (watch job id)", allocator)
	}
	items_v, has_items := obj["items"]
	if !has_items {
		return "", strings.clone("items required", allocator)
	}
	items, ierr := schedule.watch_items_normalize(items_v, allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	defer {
		for s in items {
			delete(s, allocator)
		}
		delete(items, allocator)
	}
	note := ""
	if s, s_ok := obj["note"].(json.String); s_ok {
		note = string(s)
	}
	report, n, cerr := schedule.watch_checkpoint(id, items, note, schedule.unix_now(), allocator)
	if len(cerr) > 0 {
		return "", cerr
	}
	// Hits are rare by construction, the desktop ping is the whole point
	// of a standing watch. Works headless via notify-send or a hook.
	if n > 0 {
		notify.notify_send("nullray watch", report)
	}
	return report, ""
}
