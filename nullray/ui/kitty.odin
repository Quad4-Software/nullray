// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Kitty graphics protocol helpers for inline image display.

Detection is opt-in via env or TERM/TERM_PROGRAM heuristics. Images are
emitted as base64 file payloads with unicode placeholders so terminal
cells reserve space and dirty redraw stays coherent.
*/

package ui

import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

KITTY_MAX_CHUNK :: 4096
KITTY_MAX_BYTES :: 8 * 1024 * 1024
KITTY_DEFAULT_COLS :: 40
KITTY_DEFAULT_ROWS :: 12

g_kitty_next_id: u32 = 1

kitty_graphics_enabled :: proc() -> bool {
	if v, ok := os.lookup_env("NULLRAY_KITTY_GRAPHICS", context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "auto":
			return true
		case "0", "false", "off", "no":
			return false
		}
	}
	// Explicit opt-out for limited terminals.
	if term_is_limited() {
		return false
	}
	if term, ok := os.lookup_env("TERM", context.temp_allocator); ok {
		tl := strings.to_lower(term, context.temp_allocator)
		if strings.contains(tl, "kitty") || strings.contains(tl, "ghostty") || strings.contains(tl, "wezterm") {
			return true
		}
	}
	if tp, ok := os.lookup_env("TERM_PROGRAM", context.temp_allocator); ok {
		tpl := strings.to_lower(tp, context.temp_allocator)
		if strings.contains(tpl, "kitty") || strings.contains(tpl, "ghostty") || strings.contains(tpl, "wezterm") || strings.contains(tpl, "iTerm") || strings.contains(tpl, "iterm") {
			return true
		}
	}
	if _, ok := os.lookup_env("KITTY_WINDOW_ID", context.temp_allocator); ok {
		return true
	}
	if _, ok := os.lookup_env("GHOSTTY_RESOURCES_DIR", context.temp_allocator); ok {
		return true
	}
	if _, ok := os.lookup_env("WEZTERM_EXECUTABLE", context.temp_allocator); ok {
		return true
	}
	return false
}

kitty_next_id :: proc() -> u32 {
	id := g_kitty_next_id
	if id == 0 {
		id = 1
	}
	g_kitty_next_id = id + 1
	if g_kitty_next_id == 0 {
		g_kitty_next_id = 1
	}
	return id
}

// Emit a still image at the current cursor. cols/rows are the placeholder
// cell footprint. Returns false when the terminal cannot take graphics or
// the payload is empty/too large.
kitty_draw_image_bytes :: proc(
	data: []byte,
	mime: string,
	cols, rows: int,
	id: u32 = 0,
) -> bool {
	if !kitty_graphics_enabled() || len(data) == 0 {
		return false
	}
	if len(data) > KITTY_MAX_BYTES {
		return false
	}
	c := cols
	r := rows
	if c <= 0 {
		c = KITTY_DEFAULT_COLS
	}
	if r <= 0 {
		r = KITTY_DEFAULT_ROWS
	}
	if c > 120 {
		c = 120
	}
	if r > 40 {
		r = 40
	}
	img_id := id
	if img_id == 0 {
		img_id = kitty_next_id()
	}
	fmt_code := kitty_format_code(mime)
	encoded, err := base64.encode(data, allocator = context.temp_allocator)
	if err != nil || len(encoded) == 0 {
		return false
	}
	// Chunk the payload. First chunk carries geometry; following chunks
	// only continue the payload (m=1 until last m=0).
	offset := 0
	first := true
	for offset < len(encoded) {
		end := offset + KITTY_MAX_CHUNK
		if end > len(encoded) {
			end = len(encoded)
		}
		more := end < len(encoded)
		mflag := more ? 1 : 0
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		if first {
			// a=T transmit+display, f=format, t=direct, c/r cell size,
			// C=1 do not move cursor after paint, q=2 quiet.
			fmt.sbprintf(
				&b,
				"\x1b_Ga=T,f=%d,t=d,i=%d,c=%d,r=%d,C=1,q=2,m=%d;",
				fmt_code,
				img_id,
				c,
				r,
				mflag,
			)
			first = false
		} else {
			fmt.sbprintf(&b, "\x1b_Gm=%d;", mflag)
		}
		strings.write_string(&b, encoded[offset:end])
		strings.write_string(&b, "\x1b\\")
		seq := strings.to_string(b)
		n, werr := os.write(os.stdout, transmute([]u8)seq)
		if werr != nil || n != len(seq) {
			return false
		}
		offset = end
	}
	return true
}

kitty_draw_image_file :: proc(path: string, cols, rows: int, id: u32 = 0) -> bool {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil || len(data) == 0 {
		return false
	}
	mime := kitty_mime_from_path(path)
	return kitty_draw_image_bytes(data, mime, cols, rows, id)
}

// Delete a previously displayed image by id (optional cleanup).
kitty_delete_image :: proc(id: u32) {
	if id == 0 || !kitty_graphics_enabled() {
		return
	}
	seq := fmt.tprintf("\x1b_Ga=d,d=i,i=%d,q=2\x1b\\", id)
	_, _ = os.write(os.stdout, transmute([]u8)seq)
}

kitty_format_code :: proc(mime: string) -> int {
	m := strings.to_lower(mime, context.temp_allocator)
	switch {
	case strings.contains(m, "png"):
		return 100
	case strings.contains(m, "jpeg"), strings.contains(m, "jpg"):
		return 100 // Kitty accepts jpeg as 100 with many builds; RFB uses same transmit path.
	case strings.contains(m, "gif"):
		return 100
	case strings.contains(m, "webp"):
		return 100
	case strings.contains(m, "bmp"):
		return 100
	}
	return 100
}

kitty_mime_from_path :: proc(path: string) -> string {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".bmp":
		return "image/bmp"
	}
	return "image/png"
}

// Fit image cell size into a pane while keeping a simple aspect guess.
kitty_fit_cells :: proc(max_cols, max_rows, prefer_cols, prefer_rows: int) -> (cols, rows: int) {
	c := prefer_cols
	r := prefer_rows
	if c <= 0 {
		c = KITTY_DEFAULT_COLS
	}
	if r <= 0 {
		r = KITTY_DEFAULT_ROWS
	}
	if max_cols > 0 && c > max_cols {
		c = max_cols
	}
	if max_rows > 0 && r > max_rows {
		r = max_rows
	}
	if c < 4 {
		c = min(4, max(1, max_cols))
	}
	if r < 2 {
		r = min(2, max(1, max_rows))
	}
	return c, r
}

// Probe whether a path looks like an image for UI open.
path_looks_like_image :: proc(path: string) -> bool {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp":
		return true
	}
	return false
}

