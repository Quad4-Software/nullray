// SPDX-License-Identifier: 0BSD
/*
MCP server connection and config loading.
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

connect :: proc(r: ^Registry, server_id: string, allocator := context.allocator) -> (client: ^Client, ok: bool, err: string) {
	if mcp_workspace_untrusted() {
		return nil, false, strings.clone(
			"MCP blocked: untrusted workspace (set NULLRAY_WORKSPACE_TRUST=1 after review, or NULLRAY_MCP_ALLOW_ANY=1 for trusted ad hoc use)",
			allocator,
		)
	}
	if !mcp_allow_any() && !r.allowlist[server_id] {
		return nil, false, fmt.aprintf(
			"MCP server '%s' is not allowlisted by mcp.json. Set NULLRAY_MCP_ALLOW_ANY=1 only for trusted ad hoc servers",
			server_id,
			allocator = allocator,
		)
	}
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
	if pin_err := verify_tools_pin(server_id, mcp_tools, allocator); pin_err != "" {
		remove_routes_for_server(r, server_id)
		for t in mcp_tools {
			delete(t.name)
			delete(t.description)
			delete(t.schema_json)
		}
		delete(mcp_tools)
		stdio_close(session)
		free(session)
		return nil, false, pin_err
	}
	for t in mcp_tools {
		tools.registry_register(r.tools_reg, t)
	}
	delete(mcp_tools)

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
			r.allowlist[entry.id] = true
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
		r.allowlist[id] = true
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
