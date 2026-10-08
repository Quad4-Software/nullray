// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Image paste from the system clipboard.

Tries wl-paste (Wayland), xclip, and common temp paths. Writes the bytes
to a unique path under the system temp dir and returns that path so the
app can /attach it or open it in the image pane.
*/

package ui

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

clipboard_image_paste_file :: proc(allocator := context.allocator) -> (path: string, mime: string, ok: bool) {
	// Wayland image types.
	wl_types := []string{"image/png", "image/jpeg", "image/webp", "image/bmp", "image/gif"}
	for t in wl_types {
		if data, got := clipboard_run_stdout([]string{"wl-paste", "--type", t, "--no-newline"}, context.temp_allocator); got && len(data) > 32 {
			if p, wok := clipboard_write_temp_image(transmute([]u8)data, t, allocator); wok {
				return p, t, true
			}
		}
	}
	// Generic wl-paste without type (some compositors still return png).
	if data, got := clipboard_run_stdout([]string{"wl-paste", "--no-newline"}, context.temp_allocator); got {
		if mime_guess, is_img := clipboard_sniff_image(transmute([]u8)data); is_img {
			if p, wok := clipboard_write_temp_image(transmute([]u8)data, mime_guess, allocator); wok {
				return p, mime_guess, true
			}
		}
	}
	// X11 via xclip TARGETS / image types.
	x_types := []string{"image/png", "image/jpeg", "image/bmp"}
	for t in x_types {
		if data, got := clipboard_run_stdout([]string{"xclip", "-selection", "clipboard", "-t", t, "-o"}, context.temp_allocator); got && len(data) > 32 {
			if p, wok := clipboard_write_temp_image(transmute([]u8)data, t, allocator); wok {
				return p, t, true
			}
		}
	}
	return "", "", false
}

clipboard_sniff_image :: proc(data: []u8) -> (mime: string, ok: bool) {
	if len(data) >= 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
		return "image/png", true
	}
	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return "image/jpeg", true
	}
	if len(data) >= 6 && data[0] == 'G' && data[1] == 'I' && data[2] == 'F' {
		return "image/gif", true
	}
	if len(data) >= 12 && data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
		data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P' {
		return "image/webp", true
	}
	if len(data) >= 2 && data[0] == 'B' && data[1] == 'M' {
		return "image/bmp", true
	}
	return "", false
}

@(private)
clipboard_write_temp_image :: proc(data: []u8, mime: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if len(data) == 0 {
		return "", false
	}
	ext := ".png"
	switch mime {
	case "image/jpeg":
		ext = ".jpg"
	case "image/gif":
		ext = ".gif"
	case "image/webp":
		ext = ".webp"
	case "image/bmp":
		ext = ".bmp"
	}
	dir := "/tmp"
	if t, ok := os.lookup_env("TMPDIR", context.temp_allocator); ok && len(t) > 0 {
		dir = t
	} else if t, ok := os.lookup_env("TMP", context.temp_allocator); ok && len(t) > 0 {
		dir = t
	}
	stamp := time.time_to_unix_nano(time.now())
	name := fmt.tprintf("nullray-paste-%d%s", stamp, ext)
	full, jerr := filepath.join({dir, name}, allocator)
	if jerr != nil {
		full = strings.concatenate({dir, "/", name}, allocator)
	}
	if os.write_entire_file(full, data) != nil {
		delete(full)
		return "", false
	}
	return full, true
}
