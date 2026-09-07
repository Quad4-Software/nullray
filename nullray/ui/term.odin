/*
Raw terminal mode alt screen and dirty-cell ANSI present.
*/

package ui

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Term :: struct {
	raw:        bool,
	width:      int,
	height:     int,
	out:        strings.Builder,
	prev:       Buffer,
	has_prev:   bool,
	mode:       Color_Mode,
	plat:       Term_Plat,
	alt_screen: bool,
	mouse:      bool,
}

term_init :: proc(t: ^Term, preferred_color := "") -> bool {
	t^ = {}
	t.mode = detect_color_mode(preferred_color)
	t.alt_screen = term_feature_enabled(constants.ENV_ALT_SCREEN, !term_is_limited())
	t.mouse = term_feature_enabled(constants.ENV_MOUSE, !term_is_limited())
	strings.builder_init(&t.out)
	if !term_plat_enter_raw(t) {
		return false
	}
	t.raw = true
	if t.alt_screen {
		strings.write_string(&t.out, "\x1b[?1049h")
	}
	strings.write_string(&t.out, "\x1b[2J\x1b[H\x1b[?25l")
	if t.mouse {
		strings.write_string(&t.out, "\x1b[?1000h\x1b[?1006h")
	}
	if !term_is_limited() {
		strings.write_string(&t.out, "\x1b[?2004h")
	}
	term_flush(t)
	term_query_size(t)
	return true
}

term_close :: proc(t: ^Term) {
	if t.raw {
		if !term_is_limited() {
			strings.write_string(&t.out, "\x1b[?2004l")
		}
		if t.mouse {
			strings.write_string(&t.out, "\x1b[?1006l\x1b[?1000l")
		}
		strings.write_string(&t.out, "\x1b[0m\x1b[?25h")
		if t.alt_screen {
			strings.write_string(&t.out, "\x1b[?1049l")
		}
		term_flush(t)
		term_plat_leave_raw(t)
		t.raw = false
	}
	if t.has_prev {
		buffer_destroy(&t.prev)
		t.has_prev = false
	}
	strings.builder_destroy(&t.out)
}

term_query_size :: proc(t: ^Term) {
	w, h, ok := term_plat_winsize()
	if ok && w > 0 && h > 0 {
		t.width = w
		t.height = h
		return
	}
	t.width = parse_int_env("COLUMNS", constants.DEFAULT_TERM_COLS)
	t.height = parse_int_env("LINES", constants.DEFAULT_TERM_ROWS)
	if t.width < 20 {
		t.width = constants.DEFAULT_TERM_COLS
	}
	if t.height < 5 {
		t.height = constants.DEFAULT_TERM_ROWS
	}
}

term_flush :: proc(t: ^Term) {
	s := strings.to_string(t.out)
	if len(s) > 0 {
		_, _ = os.write(os.stdout, transmute([]u8)s)
		strings.builder_reset(&t.out)
	}
}

term_invalidate :: proc(t: ^Term) {
	t.has_prev = false
}

@(private)
write_sgr :: proc(b: ^strings.Builder, mode: Color_Mode, fg, bg: Color, style: Style) {
	strings.write_string(b, "\x1b[0")
	if .Bold in style {
		strings.write_string(b, ";1")
	}
	if .Dim in style {
		strings.write_string(b, ";2")
	}
	if .Underline in style {
		strings.write_string(b, ";4")
	}
	if .Reverse in style {
		strings.write_string(b, ";7")
	}
	switch mode {
	case .None:
		strings.write_string(b, "m")
	case .Ansi16:
		fi := color_to_ansi16(fg)
		bi := color_to_ansi16(bg)
		if fi < 8 {
			fmt.sbprintf(b, ";%d", 30 + fi)
		} else {
			fmt.sbprintf(b, ";%d", 90 + (fi - 8))
		}
		if bi < 8 {
			fmt.sbprintf(b, ";%d", 40 + bi)
		} else {
			fmt.sbprintf(b, ";%d", 100 + (bi - 8))
		}
		strings.write_string(b, "m")
	case .Ansi256:
		fmt.sbprintf(b, ";38;5;%d;48;5;%dm", color_to_ansi256(fg), color_to_ansi256(bg))
	case .Truecolor:
		fmt.sbprintf(b, ";38;2;%d;%d;%d;48;2;%d;%d;%dm", fg.r, fg.g, fg.b, bg.r, bg.g, bg.b)
	}
}

term_present :: proc(t: ^Term, buf: ^Buffer) {
	term_query_size(t)
	if buf.width != t.width || buf.height != t.height {
		buffer_resize(buf, t.width, t.height)
	}

	use_diff := t.has_prev && t.prev.width == buf.width && t.prev.height == buf.height
	strings.builder_reset(&t.out)
	if !use_diff {
		strings.write_string(&t.out, "\x1b[H")
	}

	last_fg := Color{255, 255, 255}
	last_bg := Color{0, 0, 0}
	last_style: Style
	sgr_valid := false
	cursor_x := -1
	cursor_y := -1

	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			idx := y * buf.width + x
			cell := buf.cells[idx]
			if cell.ch == CELL_WIDE_CONT {
				continue
			}
			if use_diff {
				prev := t.prev.cells[idx]
				if cell.ch == prev.ch && cell.fg == prev.fg && cell.bg == prev.bg && cell.style == prev.style {
					continue
				}
				if cursor_x != x || cursor_y != y {
					fmt.sbprintf(&t.out, "\x1b[%d;%dH", y + 1, x + 1)
					cursor_x = x
					cursor_y = y
					sgr_valid = false
				}
			}
			if !sgr_valid || cell.fg != last_fg || cell.bg != last_bg || cell.style != last_style {
				write_sgr(&t.out, t.mode, cell.fg, cell.bg, cell.style)
				last_fg = cell.fg
				last_bg = cell.bg
				last_style = cell.style
				sgr_valid = true
			}
			ch := sanitize_cell_rune(cell.ch)
			strings.write_rune(&t.out, ch)
			w := max(1, rune_cols(ch))
			cursor_x = x + w
			cursor_y = y
			if cursor_x >= buf.width {
				cursor_x = 0
				cursor_y = y + 1
			}
		}
		if !use_diff && y + 1 < buf.height {
			strings.write_string(&t.out, "\r\n")
			cursor_x = 0
			cursor_y = y + 1
		}
	}
	strings.write_string(&t.out, "\x1b[0m")
	term_flush(t)

	if !t.has_prev || t.prev.width != buf.width || t.prev.height != buf.height {
		if t.has_prev {
			buffer_destroy(&t.prev)
		}
		t.prev = buffer_create(buf.width, buf.height)
		t.has_prev = true
	}
	copy(t.prev.cells, buf.cells)
}

detect_color_mode :: proc(preferred: string) -> Color_Mode {
	switch preferred {
	case "none", "0":
		return .None
	case "16", "ansi16":
		return .Ansi16
	case "256", "ansi256":
		return .Ansi256
	case "true", "truecolor", "24bit":
		return .Truecolor
	}
	if _, ok := os.lookup_env("NO_COLOR", context.temp_allocator); ok {
		return .None
	}
	if term_is_limited() {
		return .Ansi16
	}
	if colorterm, ok := os.lookup_env("COLORTERM", context.temp_allocator); ok {
		cl := strings.to_lower(colorterm, context.temp_allocator)
		if cl == "truecolor" || cl == "24bit" {
			return .Truecolor
		}
	}
	if term, ok := os.lookup_env("TERM", context.temp_allocator); ok {
		tl := strings.to_lower(term, context.temp_allocator)
		if tl == "dumb" || tl == "unknown" || tl == "" {
			return .None
		}
		if strings.contains(tl, "truecolor") || strings.contains(tl, "direct") {
			return .Truecolor
		}
		if strings.contains(tl, "256color") || strings.contains(tl, "256") {
			return .Ansi256
		}
		if strings.has_prefix(tl, "xterm") || strings.has_prefix(tl, "screen") || strings.has_prefix(tl, "tmux") ||
		   strings.has_prefix(tl, "vt") || tl == "linux" || strings.has_prefix(tl, "ansi") {
			return .Ansi16
		}
	}
	if is_wsl() {
		return .Ansi256
	}
	return .Ansi256
}

term_is_limited :: proc() -> bool {
	term, ok := os.lookup_env("TERM", context.temp_allocator)
	if !ok || len(term) == 0 {
		return true
	}
	tl := strings.to_lower(term, context.temp_allocator)
	if tl == "dumb" || tl == "unknown" || tl == "cons25" || tl == "emacs" {
		return true
	}
	return false
}

// True when UTF-8 glyphs are safe to paint.
// TERM=dumb only limits mouse and alt-screen. It does not mean ASCII-only.
// Prefer locale. Default to UTF-8 unless the charset is an explicit legacy set.
term_utf8_ok :: proc() -> bool {
	when ODIN_OS == .Windows {
		return true
	}
	for key in ([]string{"LC_ALL", "LC_CTYPE", "LANG"}) {
		if v, ok := os.lookup_env(key, context.temp_allocator); ok {
			vl := strings.trim_space(strings.to_lower(v, context.temp_allocator))
			if len(vl) == 0 {
				continue
			}
			if strings.contains(vl, "utf-8") || strings.contains(vl, "utf8") {
				return true
			}
			if vl == "c" ||
			   vl == "posix" ||
			   strings.has_prefix(vl, "c.") ||
			   strings.contains(vl, "iso-8859") ||
			   strings.contains(vl, "iso8859") ||
			   strings.contains(vl, "koi8") {
				return false
			}
		}
	}
	return true
}

is_wsl :: proc() -> bool {
	if _, ok := os.lookup_env("WSL_DISTRO_NAME", context.temp_allocator); ok {
		return true
	}
	if _, ok := os.lookup_env("WSL_INTEROP", context.temp_allocator); ok {
		return true
	}
	when ODIN_OS == .Linux {
		data, err := os.read_entire_file("/proc/version", context.temp_allocator)
		if err != nil {
			return false
		}
		v := string(data)
		return strings.contains(v, "Microsoft") || strings.contains(v, "WSL")
	}
	return false
}

term_feature_enabled :: proc(env_name: string, default_on: bool) -> bool {
	v, ok := os.lookup_env(env_name, context.temp_allocator)
	if !ok {
		return default_on
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "false", "off", "no", "disable", "disabled":
		return false
	case "1", "true", "on", "yes", "enable", "enabled":
		return true
	}
	return default_on
}

parse_int_env :: proc(name: string, fallback: int) -> int {
	v, ok := os.lookup_env(name, context.temp_allocator)
	if !ok {
		return fallback
	}
	n, n_ok := strconv.parse_int(v)
	if !n_ok || n <= 0 {
		return fallback
	}
	return n
}
