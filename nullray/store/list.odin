/*
Session listing, search, and group context.
*/

package store

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

Session_Info :: struct {
	name:     string,
	path:     string,
	preview:  string,
	group:    string,
	provider: string,
	model:    string,
}

list_sessions :: proc(allocator := context.allocator) -> []Session_Info {
	ensure_session_dir()
	dir := session_dir(context.temp_allocator)
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return {}
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	out := make([dynamic]Session_Info, allocator)
	for e in entries {
		if e.type == .Directory {
			continue
		}
		name := e.name
		if !strings.has_suffix(name, ".jsonl") {
			continue
		}
		stem := name[:len(name) - 5]
		path := named_session_path(stem, allocator)
		preview := session_preview(path, context.temp_allocator)
		meta, _ := load_session_meta(path, allocator)
		append(&out, Session_Info{
			name = strings.clone(stem, allocator),
			path = path,
			preview = strings.clone(preview, allocator),
			group = meta.group,
			provider = meta.provider,
			model = meta.model,
		})
	}
	return out[:]
}

destroy_session_infos :: proc(items: []Session_Info) {
	for it in items {
		delete(it.name)
		delete(it.path)
		delete(it.preview)
		delete(it.group)
		delete(it.provider)
		delete(it.model)
	}
	delete(items)
}

search_sessions :: proc(query: string, allocator := context.allocator) -> []Session_Info {
	q := strings.to_lower(strings.trim_space(query), context.temp_allocator)
	all := list_sessions(context.temp_allocator)
	defer destroy_session_infos(all)
	out := make([dynamic]Session_Info, 0, 8, allocator)
	if len(q) == 0 {
		for it in all {
			if len(out) >= constants.MAX_SESSION_SEARCH {
				break
			}
			append(&out, Session_Info{
				name = strings.clone(it.name, allocator),
				path = strings.clone(it.path, allocator),
				preview = strings.clone(it.preview, allocator),
				group = strings.clone(it.group, allocator),
				provider = strings.clone(it.provider, allocator),
				model = strings.clone(it.model, allocator),
			})
		}
		return out[:]
	}
	for it in all {
		if len(out) >= constants.MAX_SESSION_SEARCH {
			break
		}
		hay := fmt.tprintf("%s %s %s %s %s", it.name, it.group, it.preview, it.provider, it.model)
		if !strings.contains(strings.to_lower(hay, context.temp_allocator), q) {
			// Also scan transcript body
			if !session_body_contains(it.path, q) {
				continue
			}
		}
		append(&out, Session_Info{
			name = strings.clone(it.name, allocator),
			path = strings.clone(it.path, allocator),
			preview = strings.clone(it.preview, allocator),
			group = strings.clone(it.group, allocator),
			provider = strings.clone(it.provider, allocator),
			model = strings.clone(it.model, allocator),
		})
	}
	return out[:]
}

list_group_sessions :: proc(group: string, exclude_name: string, allocator := context.allocator) -> []Session_Info {
	g := store_sanitize_group(group)
	all := list_sessions(context.temp_allocator)
	defer destroy_session_infos(all)
	out := make([dynamic]Session_Info, 0, 4, allocator)
	for it in all {
		if len(it.group) == 0 || it.group != g {
			continue
		}
		if len(exclude_name) > 0 && it.name == exclude_name {
			continue
		}
		append(&out, Session_Info{
			name = strings.clone(it.name, allocator),
			path = strings.clone(it.path, allocator),
			preview = strings.clone(it.preview, allocator),
			group = strings.clone(it.group, allocator),
			provider = strings.clone(it.provider, allocator),
			model = strings.clone(it.model, allocator),
		})
	}
	return out[:]
}

group_context_text :: proc(group: string, exclude_name: string, allocator := context.allocator) -> string {
	if len(strings.trim_space(group)) == 0 {
		return strings.clone("", allocator)
	}
	items := list_group_sessions(group, exclude_name, context.temp_allocator)
	defer destroy_session_infos(items)
	if len(items) == 0 {
		return strings.clone("", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "Shared group context from sibling sessions:\n")
	budget := constants.MAX_GROUP_CONTEXT_CHARS
	for it in items {
		if budget <= 0 {
			break
		}
		snippet := session_group_snippet(it.path, min(budget, 2400), context.temp_allocator)
		if len(snippet) == 0 {
			continue
		}
		fmt.sbprintf(&b, "\n### session %s\n%s\n", it.name, snippet)
		budget -= len(snippet)
	}
	return strings.to_string(b)
}

