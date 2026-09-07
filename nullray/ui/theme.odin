// SPDX-License-Identifier: 0BSD
/*
Built-in themes and active theme lookup.
*/

package ui

import "core:strings"

Theme :: struct {
	name:         string,
	bg:           Color,
	fg:           Color,
	muted:        Color,
	border:       Color,
	accent:       Color,
	accent_dim:   Color,
	highlight_bg: Color,
	highlight_fg: Color,
	warn:         Color,
	ok:           Color,
	error:        Color,
	title:        Color,
	status_bg:    Color,
	status_fg:    Color,
	input_bg:     Color,
	user_fg:      Color,
	assistant_fg: Color,
}

INK :: Theme{
	name         = "ink",
	bg           = {10, 14, 18},
	fg           = {210, 214, 220},
	muted        = {110, 118, 128},
	border       = {48, 58, 70},
	accent       = {72, 168, 148},
	accent_dim   = {48, 120, 108},
	highlight_bg = {28, 36, 46},
	highlight_fg = {230, 234, 240},
	warn         = {196, 150, 70},
	ok           = {110, 170, 130},
	error        = {190, 90, 90},
	title        = {140, 200, 180},
	status_bg    = {18, 24, 32},
	status_fg    = {160, 168, 178},
	input_bg     = {16, 22, 28},
	user_fg      = {150, 190, 220},
	assistant_fg = {210, 214, 220},
}

EMBER :: Theme{
	name         = "ember",
	bg           = {14, 12, 10},
	fg           = {220, 210, 196},
	muted        = {120, 110, 100},
	border       = {70, 58, 48},
	accent       = {210, 120, 64},
	accent_dim   = {150, 90, 50},
	highlight_bg = {36, 28, 22},
	highlight_fg = {236, 224, 208},
	warn         = {200, 150, 60},
	ok           = {120, 150, 100},
	error        = {190, 80, 70},
	title        = {220, 170, 110},
	status_bg    = {22, 18, 14},
	status_fg    = {170, 160, 148},
	input_bg     = {20, 16, 12},
	user_fg      = {230, 180, 120},
	assistant_fg = {220, 210, 196},
}

MOSS :: Theme{
	name         = "moss",
	bg           = {12, 16, 12},
	fg           = {200, 214, 196},
	muted        = {100, 118, 100},
	border       = {48, 70, 52},
	accent       = {110, 170, 90},
	accent_dim   = {70, 120, 60},
	highlight_bg = {24, 34, 26},
	highlight_fg = {220, 236, 210},
	warn         = {190, 160, 70},
	ok           = {120, 180, 110},
	error        = {180, 90, 80},
	title        = {150, 200, 130},
	status_bg    = {16, 24, 18},
	status_fg    = {150, 170, 148},
	input_bg     = {14, 22, 16},
	user_fg      = {160, 200, 150},
	assistant_fg = {200, 214, 196},
}

SLATE :: Theme{
	name         = "slate",
	bg           = {16, 18, 24},
	fg           = {210, 214, 224},
	muted        = {110, 118, 136},
	border       = {50, 58, 78},
	accent       = {100, 140, 210},
	accent_dim   = {70, 100, 160},
	highlight_bg = {28, 32, 46},
	highlight_fg = {230, 234, 245},
	warn         = {200, 160, 80},
	ok           = {100, 170, 150},
	error        = {200, 100, 110},
	title        = {150, 180, 230},
	status_bg    = {20, 24, 34},
	status_fg    = {150, 160, 180},
	input_bg     = {18, 22, 30},
	user_fg      = {160, 190, 240},
	assistant_fg = {210, 214, 224},
}

ROSE :: Theme{
	name         = "rose",
	bg           = {18, 12, 16},
	fg           = {230, 210, 220},
	muted        = {140, 110, 124},
	border       = {80, 50, 64},
	accent       = {210, 110, 150},
	accent_dim   = {150, 70, 100},
	highlight_bg = {36, 24, 32},
	highlight_fg = {245, 220, 230},
	warn         = {210, 150, 90},
	ok           = {140, 170, 120},
	error        = {200, 90, 100},
	title        = {230, 150, 180},
	status_bg    = {26, 16, 22},
	status_fg    = {180, 150, 165},
	input_bg     = {22, 14, 18},
	user_fg      = {230, 170, 200},
	assistant_fg = {230, 210, 220},
}

MONO :: Theme{
	name         = "mono",
	bg           = {12, 12, 12},
	fg           = {220, 220, 220},
	muted        = {120, 120, 120},
	border       = {60, 60, 60},
	accent       = {200, 200, 200},
	accent_dim   = {140, 140, 140},
	highlight_bg = {32, 32, 32},
	highlight_fg = {240, 240, 240},
	warn         = {180, 180, 180},
	ok           = {170, 170, 170},
	error        = {160, 160, 160},
	title        = {230, 230, 230},
	status_bg    = {20, 20, 20},
	status_fg    = {160, 160, 160},
	input_bg     = {18, 18, 18},
	user_fg      = {200, 200, 200},
	assistant_fg = {220, 220, 220},
}

DUSK :: Theme{
	name         = "dusk",
	bg           = {18, 14, 28},
	fg           = {220, 214, 230},
	muted        = {120, 110, 140},
	border       = {60, 50, 90},
	accent       = {160, 120, 210},
	accent_dim   = {110, 80, 160},
	highlight_bg = {32, 26, 48},
	highlight_fg = {236, 228, 245},
	warn         = {210, 160, 90},
	ok           = {120, 180, 150},
	error        = {200, 100, 120},
	title        = {190, 160, 230},
	status_bg    = {24, 18, 36},
	status_fg    = {160, 150, 180},
	input_bg     = {22, 16, 32},
	user_fg      = {180, 170, 230},
	assistant_fg = {220, 214, 230},
}

@(private)
active_theme: Theme = INK

theme :: proc() -> Theme {
	return active_theme
}

theme_set :: proc(t: Theme) {
	active_theme = t
}

theme_names :: proc() -> []string {
	@(static) names := []string{"ink", "ember", "moss", "slate", "rose", "mono", "dusk"}
	return names
}

theme_by_name :: proc(name: string) -> Theme {
	switch strings.to_lower(strings.trim_space(name), context.temp_allocator) {
	case "ember":
		return EMBER
	case "moss":
		return MOSS
	case "slate":
		return SLATE
	case "rose":
		return ROSE
	case "mono", "monochrome":
		return MONO
	case "dusk":
		return DUSK
	case "ink", "":
		return INK
	}
	return INK
}

theme_exists :: proc(name: string) -> bool {
	n := strings.to_lower(strings.trim_space(name), context.temp_allocator)
	for t in theme_names() {
		if t == n || (n == "monochrome" && t == "mono") {
			return true
		}
	}
	return false
}
