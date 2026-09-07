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

binds_resolve :: proc(b: Binds, kind: ui.Key) -> Action {
	if kind == .None {
		return .None
	}
	if kind == b.quit || kind == .Ctrl_C {
		return .Quit
	}
	if kind == b.clear_chat {
		return .Clear_Chat
	}
	if kind == b.provider_next {
		return .Provider_Next
	}
	if kind == b.provider_prev {
		return .Provider_Prev
	}
	if kind == b.compact {
		return .Compact
	}
	if kind == b.toggle_tools {
		return .Toggle_Tools
	}
	if kind == b.clear_input {
		return .Clear_Input
	}
	if kind == b.help {
		return .Help
	}
	if kind == b.scroll_up {
		return .Scroll_Up
	}
	if kind == b.scroll_down {
		return .Scroll_Down
	}
	if kind == b.page_up {
		return .Page_Up
	}
	if kind == b.page_down {
		return .Page_Down
	}
	if kind == b.follow_bottom {
		return .Follow_Bottom
	}
	if kind == b.scroll_top {
		return .Scroll_Top
	}
	if kind == b.improve {
		return .Improve_Prompt
	}
	if kind == b.undo_improve {
		return .Undo_Improve
	}
	if kind == b.pause_agent {
		return .Pause_Agent
	}
	return .None
}

binds_help_text :: proc(b: Binds, preset: Key_Preset, allocator := context.allocator) -> string {
	edit := ""
	switch preset {
	case .Default:
		edit = "  (preset default)\n"
	case .Neovim:
		edit = "  (preset neovim) ctrl-w kill word  ctrl-u kill to start  home/end cursor\n"
	case .Emacs:
		edit = "  (preset emacs) ctrl-a/e home/end  ctrl-b/f move  ctrl-k kill-eol  ctrl-w kill word  ctrl-d del  ctrl-u kill to start\n"
	}
	return fmt.aprintf(
		"%s  %-14s quit\n  %-14s clear chat\n  %-14s next provider\n  %-14s prev provider\n  %-14s compact\n  %-14s toggle tools\n  %-14s clear input\n  %-14s help\n  %-14s scroll up\n  %-14s scroll down\n  %-14s page up\n  %-14s page down\n  %-14s follow bottom\n  %-14s scroll top\n  %-14s improve prompt\n  %-14s undo improve\n  %-14s pause agent\n  Esc            stop agent (when busy)\n  edit file     %s\n  preset via    --keys / NULLRAY_KEYS / keys.ini preset=",
		edit,
		key_name(b.quit),
		key_name(b.clear_chat),
		key_name(b.provider_next),
		key_name(b.provider_prev),
		key_name(b.compact),
		key_name(b.toggle_tools),
		key_name(b.clear_input),
		key_name(b.help),
		key_name(b.scroll_up),
		key_name(b.scroll_down),
		key_name(b.page_up),
		key_name(b.page_down),
		key_name(b.follow_bottom),
		key_name(b.scroll_top),
		key_name(b.improve),
		key_name(b.undo_improve),
		key_name(b.pause_agent),
		keys_path(context.temp_allocator),
		allocator = allocator,
	)
}

write_default_keys_file :: proc() -> bool {
	path := keys_path(context.temp_allocator)
	if _, err := os.stat(path, context.temp_allocator); err == nil {
		return true
	}
	_ = os.make_directory_all(sandbox.resolve_config_dir(context.temp_allocator))
	body := `# nullray key bindings (one action=key per line)
# preset=default|neovim|emacs  (or NULLRAY_KEYS / --keys)
# keys: ctrl-a .. ctrl-z, up, down, left, right, home, end, pageup, pagedown, f1..f4, tab, enter, esc
preset=default
quit=ctrl-q
clear_chat=ctrl-l
provider_next=ctrl-n
provider_prev=ctrl-p
compact=ctrl-r
toggle_tools=ctrl-t
clear_input=ctrl-u
help=f1
scroll_up=up
scroll_down=down
page_up=pageup
page_down=pagedown
follow_bottom=end
scroll_top=home
improve=f2
undo_improve=ctrl-z
pause=f3
`
	return os.write_entire_file(path, transmute([]u8)body) == nil
}

parse_key_name :: proc(name: string) -> (ui.Key, bool) {
	n := strings.to_lower(strings.trim_space(name), context.temp_allocator)
	switch n {
	case "ctrl-q", "c-q":
		return .Ctrl_Q, true
	case "ctrl-c", "c-c":
		return .Ctrl_C, true
	case "ctrl-l", "c-l":
		return .Ctrl_L, true
	case "ctrl-n", "c-n":
		return .Ctrl_N, true
	case "ctrl-p", "c-p":
		return .Ctrl_P, true
	case "ctrl-r", "c-r":
		return .Ctrl_R, true
	case "ctrl-t", "c-t":
		return .Ctrl_T, true
	case "ctrl-u", "c-u":
		return .Ctrl_U, true
	case "ctrl-a", "c-a":
		return .Ctrl_A, true
	case "ctrl-b", "c-b":
		return .Ctrl_B, true
	case "ctrl-d", "c-d":
		return .Ctrl_D, true
	case "ctrl-e", "c-e":
		return .Ctrl_E, true
	case "ctrl-f", "c-f":
		return .Ctrl_F, true
	case "ctrl-k", "c-k":
		return .Ctrl_K, true
	case "ctrl-w", "c-w":
		return .Ctrl_W, true
	case "ctrl-z", "c-z":
		return .Ctrl_Z, true
	case "none", "off", "-":
		return .None, true
	case "up":
		return .Up, true
	case "down":
		return .Down, true
	case "left":
		return .Left, true
	case "right":
		return .Right, true
	case "home":
		return .Home, true
	case "end":
		return .End, true
	case "pageup", "page-up", "pgup":
		return .Page_Up, true
	case "pagedown", "page-down", "pgdn":
		return .Page_Down, true
	case "f1":
		return .F1, true
	case "f2":
		return .F2, true
	case "f3":
		return .F3, true
	case "f4":
		return .F4, true
	case "tab":
		return .Tab, true
	case "enter", "return":
		return .Enter, true
	case "esc", "escape":
		return .Esc, true
	}
	return .None, false
}

key_name :: proc(k: ui.Key) -> string {
	#partial switch k {
	case .None:
		return "none"
	case .Ctrl_Q:
		return "ctrl-q"
	case .Ctrl_C:
		return "ctrl-c"
	case .Ctrl_L:
		return "ctrl-l"
	case .Ctrl_N:
		return "ctrl-n"
	case .Ctrl_P:
		return "ctrl-p"
	case .Ctrl_R:
		return "ctrl-r"
	case .Ctrl_T:
		return "ctrl-t"
	case .Ctrl_U:
		return "ctrl-u"
	case .Ctrl_A:
		return "ctrl-a"
	case .Ctrl_B:
		return "ctrl-b"
	case .Ctrl_D:
		return "ctrl-d"
	case .Ctrl_E:
		return "ctrl-e"
	case .Ctrl_F:
		return "ctrl-f"
	case .Ctrl_K:
		return "ctrl-k"
	case .Ctrl_W:
		return "ctrl-w"
	case .Ctrl_Z:
		return "ctrl-z"
	case .Up:
		return "up"
	case .Down:
		return "down"
	case .Left:
		return "left"
	case .Right:
		return "right"
	case .Home:
		return "home"
	case .End:
		return "end"
	case .Page_Up:
		return "pageup"
	case .Page_Down:
		return "pagedown"
	case .F1:
		return "f1"
	case .F2:
		return "f2"
	case .F3:
		return "f3"
	case .F4:
		return "f4"
	case .Tab:
		return "tab"
	case .Enter:
		return "enter"
	case .Esc:
		return "esc"
	}
	return "?"
}
