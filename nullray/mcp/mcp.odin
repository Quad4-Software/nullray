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
	servers: [dynamic]Server,
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
g_clients: map[string]^Client
g_tool_routes: map[string]Mcp_Tool_Route

registry :: proc() -> ^Registry {
	return &g_registry
}

mcp_init :: proc() {
	g_registry = {}
	g_registry.servers = make([dynamic]Server)
	g_clients = make(map[string]^Client)
	g_tool_routes = make(map[string]Mcp_Tool_Route)
	tools.set_external_run(mcp_run_tool)
}

mcp_destroy :: proc() {
	clients := make([dynamic]^Client, context.temp_allocator)
	for _, client in g_clients {
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
	clear(&g_clients)
	delete(g_clients)

	route_keys := make([dynamic]string, context.temp_allocator)
	for k in g_tool_routes {
		append(&route_keys, k)
	}
	for k in route_keys {
		route := g_tool_routes[k]
		delete(route.server_id)
		delete(route.tool_name)
		delete(k)
	}
	delete(g_tool_routes)
	for s in g_registry.servers {
		delete(s.id)
		delete(s.name)
		delete(s.command_or_url)
	}
	delete(g_registry.servers)
	g_registry = {}
	tools.set_external_run(nil)
}

register :: proc(s: Server) {
	for existing, i in g_registry.servers {
		if existing.id == s.id {
			delete(g_registry.servers[i].id)
			delete(g_registry.servers[i].name)
			delete(g_registry.servers[i].command_or_url)
			g_registry.servers[i] = s
			return
		}
	}
	append(&g_registry.servers, s)
}

find :: proc(id: string) -> (^Server, bool) {
	for &s in g_registry.servers {
		if s.id == id {
			return &s, true
		}
	}
	return nil, false
}

list :: proc() -> []Server {
	return g_registry.servers[:]
}

connect :: proc(server_id: string, allocator := context.allocator) -> (client: ^Client, ok: bool, err: string) {
	srv, found := find(server_id)
	if !found {
		return nil, false, fmt.aprintf("unknown MCP server: %s", server_id, allocator = allocator)
	}
	if existing, exists := g_clients[server_id]; exists && existing.connected {
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

	mcp_tools, list_err := client_list_tools(session, server_id, allocator)
	if list_err != "" {
		stdio_close(session)
		free(session)
		return nil, false, list_err
	}
	for t in mcp_tools {
		tools.register(t)
	}

	c := new(Client, allocator)
	c.server_id = strings.clone(server_id, allocator)
	c.session = session
	c.connected = true
	g_clients[server_id] = c
	return c, true, ""
}

disconnect :: proc(client: ^Client) {
	if client == nil {
		return
	}
	if client.session != nil {
		stdio_close(client.session)
		free(client.session)
		client.session = nil
	}
	delete_key(&g_clients, client.server_id)
	delete(client.server_id)
	client.connected = false
	free(client)
}

list_server_tools :: proc(server_id: string) -> []tools.Tool {
	out := make([dynamic]tools.Tool, context.temp_allocator)
	for name, route in g_tool_routes {
		if route.server_id == server_id {
			if t, ok := tools.find(name); ok {
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

load_config_from_file :: proc(path: string, allocator := context.allocator) -> (loaded: int, err: string) {
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
			register(Server{
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
		register(Server{
			id = strings.clone(id, allocator),
			name = strings.clone(name, allocator),
			command_or_url = strings.clone(command, allocator),
			transport = .Stdio,
		})
		loaded += 1
	}
	return loaded, ""
}

mcp_autoload :: proc() {
	path := config_path()
	defer delete(path)

	loaded, lerr := load_config_from_file(path)
	if lerr != "" {
		fmt.eprintf("nullray: mcp config: %s\n", lerr)
		delete(lerr)
		return
	}
	if loaded == 0 {
		return
	}

	for s in g_registry.servers {
		_, ok, cerr := connect(s.id)
		if !ok {
			fmt.eprintf("nullray: mcp server %s: %s\n", s.id, cerr)
			delete(cerr)
		}
	}
}

mcp_run_tool :: proc(name: string, args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	route, ok := g_tool_routes[name]
	if !ok {
		return "", fmt.aprintf("unknown mcp tool: %s (check ~/.config/nullray/mcp.json)", name, allocator = allocator)
	}
	client, cok := g_clients[route.server_id]
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
