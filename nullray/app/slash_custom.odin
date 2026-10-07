// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Custom slash commands from markdown. Workspace .nullray/commands and
config commands directories hold .md prompt templates. $ARGUMENTS and
$1 through $9 expand.
*/

package app

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:provider"
import "nullray:modules"
import "nullray:sandbox"
import "nullray:session"
import "nullray:skills"

Custom_Command :: struct {
	name: string,
	help: string,
	body: string,
}

@(private)
g_custom_mu: sync.Mutex
@(private)
g_custom: [dynamic]Custom_Command
@(private)
g_custom_loaded: bool

custom_commands_destroy_locked :: proc() {
	for c in g_custom {
		delete(c.name)
		delete(c.help)
		delete(c.body)
	}
	delete(g_custom)
	g_custom = nil
}

custom_commands_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_COMMANDS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable":
			return false
		}
	}
	return true
}

custom_commands_reload :: proc() {
	sync.mutex_lock(&g_custom_mu)
	defer sync.mutex_unlock(&g_custom_mu)
	custom_commands_destroy_locked()
	g_custom = make([dynamic]Custom_Command)
	g_custom_loaded = true
	if !custom_commands_enabled() {
		return
	}
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
			ws = cwd
		}
	}
	if len(ws) > 0 {
		dir, _ := filepath.join({ws, ".nullray", constants.COMMANDS_DIR}, context.temp_allocator)
		custom_load_dir(dir)
	}
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	if len(cfg) > 0 {
		dir, _ := filepath.join({cfg, constants.COMMANDS_DIR}, context.temp_allocator)
		custom_load_dir(dir)
	}
	// Compiled modules contribute prompt-template commands too.
	for m in modules.modules_list() {
		for c in m.commands {
			if len(c.name) == 0 || len(c.prompt) == 0 {
				continue
			}
			help := c.help
			if len(help) == 0 {
				help = "module command"
			}
			append(&g_custom, Custom_Command{
				name = strings.clone(c.name),
				help = strings.clone(help),
				body = strings.clone(c.prompt),
			})
		}
	}
}

@(private)
custom_load_dir :: proc(dir: string) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for e in entries {
		if e.type == .Directory || !strings.has_suffix(e.name, ".md") {
			continue
		}
		fpath, ferr := filepath.join({dir, e.name}, context.temp_allocator)
		if ferr != nil {
			continue
		}
		data, rerr := os.read_entire_file(fpath, context.temp_allocator)
		if rerr != nil || len(data) == 0 {
			continue
		}
		id := e.name[:len(e.name) - 3]
		meta, body := skills.split_frontmatter(string(data))
		name, desc := skills.parse_frontmatter_fields(meta, context.temp_allocator)
		cmd_name := id
		if len(name) > 0 {
			cmd_name = name
		}
		help := desc
		if len(help) == 0 {
			help = "custom command"
		}
		append(&g_custom, Custom_Command{
			name = strings.clone(cmd_name),
			help = strings.clone(help),
			body = strings.clone(body),
		})
	}
}

custom_commands_ensure :: proc() {
	sync.mutex_lock(&g_custom_mu)
	loaded := g_custom_loaded
	sync.mutex_unlock(&g_custom_mu)
	if !loaded {
		custom_commands_reload()
	}
}

custom_command_find :: proc(name: string) -> (Custom_Command, bool) {
	custom_commands_ensure()
	sync.mutex_lock(&g_custom_mu)
	defer sync.mutex_unlock(&g_custom_mu)
	for c in g_custom {
		if c.name == name {
			return c, true
		}
	}
	return {}, false
}

custom_command_matches :: proc(prefix: string, allocator := context.temp_allocator) -> []Slash_Command {
	custom_commands_ensure()
	out := make([dynamic]Slash_Command, 0, 4, allocator)
	sync.mutex_lock(&g_custom_mu)
	defer sync.mutex_unlock(&g_custom_mu)
	for c in g_custom {
		if len(prefix) == 0 || strings.has_prefix(c.name, prefix) {
			append(&out, Slash_Command{
				name = c.name,
				usage = strings.concatenate({"/", c.name, " [args]"}, allocator),
				help = c.help,
			})
		}
	}
	return out[:]
}

expand_command_template :: proc(body, args: string, allocator := context.allocator) -> string {
	s := body
	s, _ = strings.replace_all(s, "$ARGUMENTS", args, context.temp_allocator)
	fields := strings.fields(args, context.temp_allocator)
	for i in 0 ..< 9 {
		key := strings.concatenate({"$", fmt_n(i + 1)}, context.temp_allocator)
		val := ""
		if i < len(fields) {
			val = fields[i]
		}
		s, _ = strings.replace_all(s, key, val, context.temp_allocator)
	}
	return strings.clone(s, allocator)
}

@(private)
fmt_n :: proc(n: int) -> string {
	switch n {
	case 1:
		return "1"
	case 2:
		return "2"
	case 3:
		return "3"
	case 4:
		return "4"
	case 5:
		return "5"
	case 6:
		return "6"
	case 7:
		return "7"
	case 8:
		return "8"
	case 9:
		return "9"
	}
	return "0"
}

slash_cmd_custom :: proc(a: ^App, name, args: string) {
	cmd, ok := custom_command_find(name)
	if !ok {
		session.session_set_status(a.session, "unknown custom command")
		return
	}
	prompt := expand_command_template(cmd.body, args)
	defer delete(prompt)
	text := strings.trim_space(prompt)
	if len(text) == 0 {
		session.session_set_status(a.session, "empty custom command body")
		return
	}
	session.session_push_user(a.session, text)
	p := provider.registry_active(&a.registry)
	session.session_start_chat(a.session, p)
}
