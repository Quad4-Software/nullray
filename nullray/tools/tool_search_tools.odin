// SPDX-License-Identifier: 0BSD
/*
search_tools: discover deferred tool schemas and activate them for lean prompts.
*/

package tools

import "core:fmt"
import "core:strings"
import "core:sync"

@(private)
g_deferred_mu: sync.Mutex

@(private)
g_deferred_names: [dynamic]string

deferred_clear :: proc() {
	sync.mutex_lock(&g_deferred_mu)
	defer sync.mutex_unlock(&g_deferred_mu)
	for n in g_deferred_names {
		delete(n)
	}
	delete(g_deferred_names)
	g_deferred_names = make([dynamic]string)
}

deferred_activate :: proc(name: string) {
	trimmed := strings.trim_space(name)
	if len(trimmed) == 0 {
		return
	}
	sync.mutex_lock(&g_deferred_mu)
	defer sync.mutex_unlock(&g_deferred_mu)
	for n in g_deferred_names {
		if n == trimmed {
			return
		}
	}
	append(&g_deferred_names, strings.clone(trimmed))
}

deferred_active :: proc(name: string) -> bool {
	sync.mutex_lock(&g_deferred_mu)
	defer sync.mutex_unlock(&g_deferred_mu)
	for n in g_deferred_names {
		if n == name {
			return true
		}
	}
	return false
}

tool_search_tools :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	query, qerr := json_arg_string(args_json, "query", allocator)
	if qerr != "" {
		return "", qerr
	}
	defer delete(query)
	needle := strings.to_lower(strings.trim_space(query), context.temp_allocator)
	if len(needle) == 0 {
		return "", strings.clone("query required", allocator)
	}
	r := registry()
	b: strings.Builder
	strings.builder_init(&b, allocator)
	n := 0
	for t in r.tools {
		hay := fmt.tprintf("%s %s", t.name, t.description)
		hay_l := strings.to_lower(hay, context.temp_allocator)
		exact := strings.to_lower(t.name, context.temp_allocator) == needle
		if !exact && !strings.contains(hay_l, needle) {
			continue
		}
		deferred_activate(t.name)
		fmt.sbprintf(&b, "name: %s\nkind: %v\ndescription: %s\nschema: %s\n\n", t.name, t.kind, t.description, t.schema_json)
		n += 1
		if n >= 12 {
			break
		}
	}
	if n == 0 {
		strings.write_string(&b, "(no matches)")
	} else {
		fmt.sbprintf(&b, "activated %d tool(s) for subsequent turns\n", n)
	}
	return strings.to_string(b), ""
}
