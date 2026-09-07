// SPDX-License-Identifier: 0BSD
/*
MCP server registry, stdio client connections, and tool registration.
*/

package mcp

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"
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
		delete(route.server_id)
		delete(route.tool_name)
		delete(k)
	}
	delete(r.tool_routes)
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

connect :: proc(r: ^Registry, server_id: string, allocator := context.allocator) -> (client: ^Client, ok: bool, err: string) {
	srv, found := find(r, server_id)
	if !found {
		return nil, false, fmt.aprintf("unknown MCP server: %s", server_id, allocator = allocator)
	}
	if existing, exists := r.clients[server_id]; exists && existing.connected {
		return existing, true, ""
	}

	argv := split_command_argv(srv.command_or_url, allocator)
	defer {
		for arg in argv {
			delete(arg)
		}
		delete(argv)
	}
	if len(argv) == 0 {
		return nil, false, strings.clone("empty MCP command", allocator)
	}

	cwd := workspace_cwd(allocator)
	defer delete(cwd)

	session := new(Stdio_Session, allocator)
	if start_err := stdio_start(session, argv[:], cwd); start_err != "" {
		free(session)
		return nil, false, strings.clone(start_err, allocator)
	}

	if init_err := client_initialize(session, allocator); init_err != "" {
		stdio_close(session)
		free(session)
		return nil, false, init_err
	}

	mcp_tools, list_err := client_list_tools(session, server_id, &r.tool_routes, allocator)
	if list_err != "" {
		stdio_close(session)
		free(session)
		return nil, false, list_err
	}
	for t in mcp_tools {
		tools.registry_register(r.tools_reg, t)
	}

	c := new(Client, allocator)
	c.server_id = strings.clone(server_id, allocator)
	c.session = session
	c.connected = true
	r.clients[server_id] = c
	return c, true, ""
}

disconnect :: proc(r: ^Registry, client: ^Client) {
	if client == nil {
		return
	}
	if client.session != nil {
		stdio_close(client.session)
		free(client.session)
		client.session = nil
	}
	if r != nil {
		delete_key(&r.clients, client.server_id)
	}
	delete(client.server_id)
	client.connected = false
	free(client)
}

list_server_tools :: proc(r: ^Registry, server_id: string) -> []tools.Tool {
	out := make([dynamic]tools.Tool, context.temp_allocator)
	if r == nil {
		return out[:]
	}
	for name, route in r.tool_routes {
		if route.server_id == server_id {
			if t, ok := tools.registry_find(r.tools_reg, name); ok {
				append(&out, t^)
			}
		}
		_ = name
	}
	return out[:]
}

config_path :: proc(allocator := context.allocator) -> string {
	base := sandbox.resolve_config_dir(context.temp_allocator)
	joined, err := filepath.join({base, constants.MCP_CONFIG_FILE}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", base, constants.MCP_CONFIG_FILE, allocator = allocator)
	}
	return joined
}

load_config_from_file :: proc(r: ^Registry, path: string, allocator := context.allocator) -> (loaded: int, err: string) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		if read_err == os.General_Error.Not_Exist {
			return 0, ""
		}
		return 0, fmt.aprintf("read mcp config failed: %v", read_err, allocator = allocator)
	}
	defer delete(data)

	text := strings.trim_space(string(data))
	if len(text) == 0 {
		return 0, ""
	}

	if strings.has_prefix(text, "{") {
		cfg: Config_File
		if uerr := json.unmarshal(data, &cfg, .JSON, allocator); uerr != nil {
			return 0, fmt.aprintf("parse mcp config JSON failed: %v", uerr, allocator = allocator)
		}
		for entry in cfg.servers {
			if len(entry.id) == 0 || len(entry.command) == 0 {
				continue
			}
			name := entry.name
			if len(name) == 0 {
				name = entry.id
			}
			register(r, Server{
				id = strings.clone(entry.id, allocator),
				name = strings.clone(name, allocator),
				command_or_url = strings.clone(entry.command, allocator),
				transport = .Stdio,
			})
			loaded += 1
		}
		return loaded, ""
	}

	lines := strings.split_lines(string(data), context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") {
			continue
		}
		parts := strings.split(trimmed, "|", context.temp_allocator)
		if len(parts) < 3 {
			continue
		}
		id := strings.trim_space(parts[0])
		name := strings.trim_space(parts[1])
		cmd_parts := parts[2:]
		command := strings.join(cmd_parts, "|", context.temp_allocator)
		command = strings.trim_space(command)
		if len(id) == 0 || len(command) == 0 {
			continue
		}
		if len(name) == 0 {
			name = id
		}
		register(r, Server{
			id = strings.clone(id, allocator),
			name = strings.clone(name, allocator),
			command_or_url = strings.clone(command, allocator),
			transport = .Stdio,
		})
		loaded += 1
	}
	return loaded, ""
}

mcp_autoload :: proc(r: ^Registry = nil) {
	reg := r
	if reg == nil {
		reg = &g_registry
	}
	path := config_path()
	defer delete(path)

	loaded, lerr := load_config_from_file(reg, path)
	if lerr != "" {
		fmt.eprintf("nullray: mcp config: %s\n", lerr)
		delete(lerr)
		return
	}
	if loaded == 0 {
		return
	}

	for s in reg.servers {
		_, ok, cerr := connect(reg, s.id)
		if !ok {
			fmt.eprintf("nullray: mcp server %s: %s\n", s.id, cerr)
			delete(cerr)
		}
	}
}

mcp_run_tool :: proc(user: rawptr, name: string, args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	r := cast(^Registry)user
	if r == nil {
		return "", strings.clone("mcp registry missing", allocator)
	}
	route, ok := r.tool_routes[name]
	if !ok {
		return "", fmt.aprintf("unknown mcp tool: %s (check ~/.config/nullray/mcp.json)", name, allocator = allocator)
	}
	client, cok := r.clients[route.server_id]
	if !cok || client == nil || !client.connected || client.session == nil {
		return "", fmt.aprintf(
			"mcp server '%s' not connected (start server or fix command in mcp.json)",
			route.server_id,
			allocator = allocator,
		)
	}
	out, cerr := client_call_tool(client.session, route.tool_name, args_json, allocator)
	if len(cerr) > 0 {
		return "", fmt.aprintf("mcp:%s:%s: %s", route.server_id, route.tool_name, cerr, allocator = allocator)
	}
	return out, ""
}

@(private)
split_command_argv :: proc(command: string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	cmd := strings.clone(command, context.temp_allocator)
	for part in strings.split_iterator(&cmd, " ") {
		p := strings.trim_space(part)
		if len(p) > 0 {
			append(&out, strings.clone(p, allocator))
		}
	}
	return out
}

@(private)
workspace_cwd :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}
