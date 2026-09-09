// SPDX-License-Identifier: 0BSD
/*
MCP server registry, stdio client connections, and tool registration.
*/

package mcp

import "nullray:tools"

Transport :: enum {
	Stdio,
	Http,
}

Server :: struct {
	id:             string,
	name:           string,
	command_or_url: string,
	transport:      Transport,
}

Client :: struct {
	server_id: string,
	session:   ^Stdio_Session,
	connected: bool,
}

Mcp_Tool_Route :: struct {
	server_id: string,
	tool_name: string,
}

Registry :: struct {
	servers:     [dynamic]Server,
	clients:     map[string]^Client,
	tool_routes: map[string]Mcp_Tool_Route,
	allowlist:   map[string]bool,
	tools_reg:   ^tools.Registry,
}

Config_Server :: struct {
	id:      string `json:"id"`,
	name:    string `json:"name"`,
	command: string `json:"command"`,
}

Config_File :: struct {
	servers: []Config_Server `json:"servers"`,
}

g_registry: Registry

registry :: proc() -> ^Registry {
	return &g_registry
}

registry_init :: proc(r: ^Registry, tools_reg: ^tools.Registry) {
	r^ = {}
	r.servers = make([dynamic]Server)
	r.clients = make(map[string]^Client)
	r.tool_routes = make(map[string]Mcp_Tool_Route)
	r.allowlist = make(map[string]bool)
	r.tools_reg = tools_reg
	if tools_reg != nil {
		tools.registry_set_external_run(tools_reg, mcp_run_tool, r)
	}
}

registry_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	clients := make([dynamic]^Client, context.temp_allocator)
	for _, client in r.clients {
		append(&clients, client)
	}
	for client in clients {
		if client.session != nil {
			stdio_close(client.session)
			free(client.session)
		}
		delete(client.server_id)
		free(client)
	}
	clear(&r.clients)
	delete(r.clients)

	route_keys := make([dynamic]string, context.temp_allocator)
	for k in r.tool_routes {
		append(&route_keys, k)
	}
	for k in route_keys {
		route := r.tool_routes[k]
		if t, ok := tools.registry_find(r.tools_reg, k); ok {
			delete(t.description)
			delete(t.schema_json)
			t.description = ""
			t.schema_json = ""
		}
		delete(route.server_id)
		delete(route.tool_name)
		delete(k)
	}
	delete(r.tool_routes)
	delete(r.allowlist)
	for s in r.servers {
		delete(s.id)
		delete(s.name)
		delete(s.command_or_url)
	}
	delete(r.servers)
	if r.tools_reg != nil {
		tools.registry_set_external_run(r.tools_reg, nil, nil)
	}
	r^ = {}
}

mcp_init :: proc() {
	registry_init(&g_registry, tools.registry())
}

mcp_destroy :: proc() {
	registry_destroy(&g_registry)
}

register :: proc(r: ^Registry, s: Server) {
	if r == nil {
		return
	}
	for existing, i in r.servers {
		if existing.id == s.id {
			delete(r.servers[i].id)
			delete(r.servers[i].name)
			delete(r.servers[i].command_or_url)
			r.servers[i] = s
			return
		}
	}
	append(&r.servers, s)
}

find :: proc(r: ^Registry, id: string) -> (^Server, bool) {
	if r == nil {
		return nil, false
	}
	for &s in r.servers {
		if s.id == id {
			return &s, true
		}
	}
	return nil, false
}

list :: proc(r: ^Registry) -> []Server {
	if r == nil {
		return {}
	}
	return r.servers[:]
}
