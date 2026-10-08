// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Small built-in banner fonts. No external figlet binary required.
*/

package art

import "core:strings"
import "nullray:ui"

// 5 rows x variable width, '#' = ink. Covers A-Z 0-9 and a few symbols.
FIG_H :: 5

@(private)
fig_glyph :: proc(ch: rune) -> [FIG_H]string {
	c := ch
	if c >= 'a' && c <= 'z' {
		c = c - 32
	}
	switch c {
	case 'A':
		return {" # ", "# #", "###", "# #", "# #"}
	case 'B':
		return {"## ", "# #", "## ", "# #", "## "}
	case 'C':
		return {" ##", "#  ", "#  ", "#  ", " ##"}
	case 'D':
		return {"## ", "# #", "# #", "# #", "## "}
	case 'E':
		return {"###", "#  ", "## ", "#  ", "###"}
	case 'F':
		return {"###", "#  ", "## ", "#  ", "#  "}
	case 'G':
		return {" ##", "#  ", "# #", "# #", " ##"}
	case 'H':
		return {"# #", "# #", "###", "# #", "# #"}
	case 'I':
		return {"###", " # ", " # ", " # ", "###"}
	case 'J':
		return {"###", "  #", "  #", "# #", " # "}
	case 'K':
		return {"# #", "# #", "## ", "# #", "# #"}
	case 'L':
		return {"#  ", "#  ", "#  ", "#  ", "###"}
	case 'M':
		return {"# #", "###", "###", "# #", "# #"}
	case 'N':
		return {"# #", "###", "###", "###", "# #"}
	case 'O':
		return {" # ", "# #", "# #", "# #", " # "}
	case 'P':
		return {"## ", "# #", "## ", "#  ", "#  "}
	case 'Q':
		return {" # ", "# #", "# #", " ##", "  #"}
	case 'R':
		return {"## ", "# #", "## ", "# #", "# #"}
	case 'S':
		return {" ##", "#  ", " # ", "  #", "## "}
	case 'T':
		return {"###", " # ", " # ", " # ", " # "}
	case 'U':
		return {"# #", "# #", "# #", "# #", " # "}
	case 'V':
		return {"# #", "# #", "# #", " # ", " # "}
	case 'W':
		return {"# #", "# #", "###", "###", "# #"}
	case 'X':
		return {"# #", "# #", " # ", "# #", "# #"}
	case 'Y':
		return {"# #", "# #", " # ", " # ", " # "}
	case 'Z':
		return {"###", "  #", " # ", "#  ", "###"}
	case '0':
		return {" # ", "# #", "# #", "# #", " # "}
	case '1':
		return {" # ", "## ", " # ", " # ", "###"}
	case '2':
		return {"## ", "  #", " # ", "#  ", "###"}
	case '3':
		return {"## ", "  #", " ##", "  #", "## "}
	case '4':
		return {"# #", "# #", "###", "  #", "  #"}
	case '5':
		return {"###", "#  ", "## ", "  #", "## "}
	case '6':
		return {" ##", "#  ", "## ", "# #", " # "}
	case '7':
		return {"###", "  #", " # ", " # ", " # "}
	case '8':
		return {" # ", "# #", " # ", "# #", " # "}
	case '9':
		return {" # ", "# #", " ##", "  #", "## "}
	case ' ':
		return {"  ", "  ", "  ", "  ", "  "}
	case '-':
		return {"   ", "   ", "###", "   ", "   "}
	case '_':
		return {"   ", "   ", "   ", "   ", "###"}
	case '.':
		return {" ", " ", " ", " ", "#"}
	case '!':
		return {"#", "#", "#", " ", "#"}
	case '?':
		return {"## ", "  #", " # ", "   ", " # "}
	case '+':
		return {"   ", " # ", "###", " # ", "   "}
	case '=':
		return {"   ", "###", "   ", "###", "   "}
	case ':':
		return {" ", "#", " ", "#", " "}
	case '/':
		return {"  #", "  #", " # ", "#  ", "#  "}
	case '\\':
		return {"#  ", "#  ", " # ", "  #", "  #"}
	case '#':
		return {"# #", "###", "# #", "###", "# #"}
	case '*':
		return {"# #", " # ", "###", " # ", "# #"}
	case '<':
		return {"  #", " # ", "#  ", " # ", "  #"}
	case '>':
		return {"#  ", " # ", "  #", " # ", "#  "}
	case '(':
		return {" #", "# ", "# ", "# ", " #"}
	case ')':
		return {"# ", " #", " #", " #", "# "}
	case '[':
		return {"##", "# ", "# ", "# ", "##"}
	case ']':
		return {"##", " #", " #", " #", "##"}
	case '\'', '`':
		return {"#", "#", " ", " ", " "}
	case '"':
		return {"# #", "# #", "   ", "   ", "   "}
	case ',':
		return {" ", " ", " ", " #", "# "}
	case '@':
		return {" # ", "# #", "###", "#  ", " ##"}
	case '%':
		return {"# #", "  #", " # ", "#  ", "# #"}
	case '&':
		return {" # ", "# #", " ##", "# #", " ##"}
	}
	// unknown: block
	return {"###", "# #", "# #", "# #", "###"}
}

fig_width :: proc(text: string) -> int {
	w := 0
	for r in text {
		g := fig_glyph(r)
		gw := 0
		for row in g {
			if len(row) > gw {
				gw = len(row)
			}
		}
		w += gw + 1
	}
	if w > 0 {
		w -= 1
	}
	return w
}

// Draw banner text. Returns width used.
canvas_figlet :: proc(c: ^Canvas, text: string, x, y: int, fg: ui.Color = {}, has_fg := false) -> int {
	if c == nil || len(text) == 0 {
		return 0
	}
	cx := x
	ink := canvas_ink(c)
	for r in text {
		g := fig_glyph(r)
		gw := 0
		for row in g {
			if len(row) > gw {
				gw = len(row)
			}
		}
		for row in 0 ..< FIG_H {
			line := g[row]
			for col := 0; col < len(line); col += 1 {
				ch := rune(line[col])
				if ch == '#' {
					canvas_put(c, cx + col, y + row, ink, fg, has_fg)
				}
			}
		}
		cx += gw + 1
	}
	return cx - x
}

// Convenience: render figlet to owned multiline string.
figlet_string :: proc(text: string, unicode := true, allocator := context.allocator) -> string {
	w := fig_width(text)
	if w < 1 {
		w = 8
	}
	c := canvas_create(w, FIG_H, unicode, '#', context.temp_allocator)
	_ = canvas_figlet(&c, text, 0, 0)
	return canvas_to_string(&c, allocator)
}
