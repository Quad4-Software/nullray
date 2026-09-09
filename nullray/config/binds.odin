// SPDX-License-Identifier: 0BSD
/*
Customizable key bindings loaded from ~/.config/nullray/keys.ini.
Presets: default, neovim (insert-style edits), emacs (readline-style edits).
*/

package config

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:ui"

Action :: enum {
	None,
	Quit,
	Clear_Chat,
	Provider_Next,
	Provider_Prev,
	Compact,
	Toggle_Tools,
	Clear_Input,
	Help,
	Scroll_Up,
	Scroll_Down,
	Page_Up,
	Page_Down,
	Follow_Bottom,
	Scroll_Top,
	Improve_Prompt,
	Undo_Improve,
	Stop_Agent,
	Pause_Agent,
}

Key_Preset :: enum {
	Default,
	Neovim,
	Emacs,
}

Binds :: struct {
	quit:          ui.Key,
	clear_chat:    ui.Key,
	provider_next: ui.Key,
	provider_prev: ui.Key,
	compact:       ui.Key,
	toggle_tools:  ui.Key,
	clear_input:   ui.Key,
	help:          ui.Key,
	scroll_up:     ui.Key,
	scroll_down:   ui.Key,
	page_up:       ui.Key,
	page_down:     ui.Key,
	follow_bottom: ui.Key,
	scroll_top:    ui.Key,
	improve:       ui.Key,
	undo_improve:  ui.Key,
	stop_agent:    ui.Key,
	pause_agent:   ui.Key,
}

binds_defaults :: proc() -> Binds {
	return Binds{
		quit = .Ctrl_Q,
		clear_chat = .Ctrl_L,
		provider_next = .Ctrl_N,
		provider_prev = .Ctrl_P,
		compact = .Ctrl_R,
		toggle_tools = .Ctrl_T,
		clear_input = .Ctrl_U,
		help = .F1,
		scroll_up = .Up,
		scroll_down = .Down,
		page_up = .Page_Up,
		page_down = .Page_Down,
		follow_bottom = .End,
		scroll_top = .Home,
		improve = .F2,
		undo_improve = .Ctrl_Z,
		stop_agent = .Esc,
		pause_agent = .F3,
	}
}

/*
Neovim-flavored chords for the input line (insert-mode style).
Home/End stay free for the cursor. Transcript scroll uses Page Up/Down.
*/
binds_neovim :: proc() -> Binds {
	b := binds_defaults()
	b.clear_input = .None
	b.follow_bottom = .None
	b.scroll_top = .None
	b.scroll_up = .None
	b.scroll_down = .None
	return b
}

/*
Emacs / readline chords for the input line.
*/
binds_emacs :: proc() -> Binds {
	b := binds_defaults()
	b.clear_input = .None
	b.follow_bottom = .None
	b.scroll_top = .None
	b.scroll_up = .None
	b.scroll_down = .None
	return b
}

preset_from_name :: proc(name: string) -> (Key_Preset, bool) {
	n := strings.to_lower(strings.trim_space(name), context.temp_allocator)
	switch n {
	case "", "default", "std", "standard":
		return .Default, true
	case "neovim", "nvim", "vim":
		return .Neovim, true
	case "emacs", "readline":
		return .Emacs, true
	}
	return .Default, false
}

preset_name :: proc(p: Key_Preset) -> string {
	switch p {
	case .Default:
		return "default"
	case .Neovim:
		return "neovim"
	case .Emacs:
		return "emacs"
	}
	return "default"
}

preset_from_env :: proc() -> Key_Preset {
	if v, ok := os.lookup_env(constants.ENV_KEYS, context.temp_allocator); ok {
		if p, pok := preset_from_name(v); pok {
			return p
		}
	}
	return .Default
}

binds_for_preset :: proc(p: Key_Preset) -> Binds {
	switch p {
	case .Default:
		return binds_defaults()
	case .Neovim:
		return binds_neovim()
	case .Emacs:
		return binds_emacs()
	}
	return binds_defaults()
}

keys_path :: proc(allocator := context.allocator) -> string {
	base := sandbox.resolve_config_dir(context.temp_allocator)
	joined, err := filepath.join({base, "keys.ini"}, allocator)
	if err != nil {
		return fmt.aprintf("%s/keys.ini", base, allocator = allocator)
	}
	return joined
}

load_binds :: proc() -> (Binds, Key_Preset) {
	path := keys_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)

	p := Key_Preset.Default
	if err == nil {
		lines := strings.split_lines(string(data), context.temp_allocator)
		for raw in lines {
			line := strings.trim_space(raw)
			if len(line) == 0 || strings.has_prefix(line, "#") || strings.has_prefix(line, "[") {
				continue
			}
			eq := strings.index_byte(line, '=')
			if eq <= 0 {
				continue
			}
			key := strings.trim_space(line[:eq])
			val := strings.trim_space(line[eq + 1:])
			if key == "preset" || key == "keys" {
				if fp, ok := preset_from_name(val); ok {
					p = fp
				}
			}
		}
	}
	// NULLRAY_KEYS / --keys overrides keys.ini preset=
	if _, ok := os.lookup_env(constants.ENV_KEYS, context.temp_allocator); ok {
		p = preset_from_env()
	}

	b := binds_for_preset(p)
	if err != nil {
		return b, p
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	for raw in lines {
		line := strings.trim_space(raw)
		if len(line) == 0 || strings.has_prefix(line, "#") || strings.has_prefix(line, "[") {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		val := strings.trim_space(line[eq + 1:])
		if key == "preset" || key == "keys" {
			continue
		}
		k, ok := parse_key_name(val)
		if !ok {
			continue
		}
		switch key {
		case "quit":
			b.quit = k
		case "clear_chat", "clear":
			b.clear_chat = k
		case "provider_next":
			b.provider_next = k
		case "provider_prev":
			b.provider_prev = k
		case "compact":
			b.compact = k
		case "toggle_tools", "tools":
			b.toggle_tools = k
		case "clear_input":
			b.clear_input = k
		case "help":
			b.help = k
		case "scroll_up":
			b.scroll_up = k
		case "scroll_down":
			b.scroll_down = k
		case "page_up":
			b.page_up = k
		case "page_down":
			b.page_down = k
		case "follow_bottom", "follow":
			b.follow_bottom = k
		case "scroll_top", "top":
			b.scroll_top = k
		case "improve", "improve_prompt":
			b.improve = k
		case "undo_improve", "undo":
			b.undo_improve = k
		case "stop", "stop_agent":
			b.stop_agent = k
		case "pause", "pause_agent":
			b.pause_agent = k
		}
	}
	return b, p
}
