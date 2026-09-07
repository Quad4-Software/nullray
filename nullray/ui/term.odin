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
	raw:      bool,
	width:    int,
	height:   int,
	out:      strings.Builder,
	prev:     Buffer,
	has_prev: bool,
	mode:     Color_Mode,
	plat:     Term_Plat,
}

term_init :: proc(t: ^Term, preferred_color := "") -> bool {
	t^ = {}
	t.mode = detect_color_mode(preferred_color)
	strings.builder_init(&t.out)
	if !term_plat_enter_raw(t) {
		return false
	}
	t.raw = true
	// Alt screen, hide cursor, SGR mouse + wheel reporting
	strings.write_string(&t.out, "\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[?2004h")
	term_flush(t)
	term_query_size(t)
	return true
}

term_close :: proc(t: ^Term) {
	if t.raw {
		strings.write_string(&t.out, "\x1b[?2004l\x1b[?1006l\x1b[?1000l\x1b[0m\x1b[?25h\x1b[?1049l")
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
	if colorterm, ok := os.lookup_env("COLORTERM", context.temp_allocator); ok {
		if colorterm == "truecolor" || colorterm == "24bit" {
			return .Truecolor
		}
	}
	if term, ok := os.lookup_env("TERM", context.temp_allocator); ok {
		if strings.contains(term, "256color") {
			return .Ansi256
		}
		if term == "dumb" {
			return .None
		}
	}
	return .Truecolor
}

parse_int_env :: proc(name: string, fallback: int) -> int {
	v, ok := os.lookup_env(name, context.temp_allocator)
	if !ok {
		return fallback
	}
	n, n_ok := strconv.parse_int(v)
	if !n_ok {
		return fallback
	}
	return n
}
