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
	user_bg:      Color,
	assistant_fg: Color,
	code_bg:      Color,
}

INK :: Theme{
	name         = "ink",
	bg           = {8, 11, 14},
	fg           = {214, 218, 224},
	muted        = {104, 114, 126},
	border       = {38, 48, 58},
	accent       = {78, 176, 154},
	accent_dim   = {44, 112, 100},
	highlight_bg = {22, 30, 38},
	highlight_fg = {232, 236, 242},
	warn         = {200, 156, 72},
	ok           = {112, 176, 136},
	error        = {210, 98, 98},
	title        = {148, 208, 186},
	status_bg    = {14, 20, 26},
	status_fg    = {148, 158, 170},
	input_bg     = {12, 18, 24},
	user_fg      = {154, 196, 228},
	user_bg      = {14, 20, 28},
	assistant_fg = {214, 218, 224},
	code_bg      = {16, 22, 30},
}

EMBER :: Theme{
	name         = "ember",
	bg           = {12, 10, 8},
	fg           = {224, 214, 200},
	muted        = {118, 108, 98},
	border       = {62, 50, 40},
	accent       = {214, 124, 66},
	accent_dim   = {148, 86, 46},
	highlight_bg = {32, 24, 18},
	highlight_fg = {240, 228, 212},
	warn         = {204, 154, 62},
	ok           = {124, 156, 104},
	error        = {200, 86, 74},
	title        = {224, 174, 114},
	status_bg    = {20, 16, 12},
	status_fg    = {168, 156, 144},
	input_bg     = {18, 14, 10},
	user_fg      = {234, 186, 126},
	user_bg      = {22, 16, 12},
	assistant_fg = {224, 214, 200},
	code_bg      = {20, 14, 10},
}

MOSS :: Theme{
	name         = "moss",
	bg           = {10, 14, 10},
	fg           = {204, 218, 200},
	muted        = {96, 114, 96},
	border       = {42, 62, 46},
	accent       = {114, 176, 94},
	accent_dim   = {66, 116, 56},
	highlight_bg = {20, 30, 22},
	highlight_fg = {224, 240, 214},
	warn         = {194, 164, 72},
	ok           = {124, 184, 114},
	error        = {188, 94, 84},
	title        = {154, 206, 134},
	status_bg    = {14, 22, 16},
	status_fg    = {146, 166, 144},
	input_bg     = {12, 20, 14},
	user_fg      = {164, 206, 154},
	user_bg      = {14, 22, 16},
	assistant_fg = {204, 218, 200},
	code_bg      = {14, 22, 16},
}

SLATE :: Theme{
	name         = "slate",
	bg           = {14, 16, 22},
	fg           = {214, 218, 228},
	muted        = {106, 114, 132},
	border       = {44, 52, 72},
	accent       = {104, 146, 216},
	accent_dim   = {66, 96, 156},
	highlight_bg = {24, 28, 42},
	highlight_fg = {234, 238, 248},
	warn         = {204, 164, 82},
	ok           = {104, 174, 154},
	error        = {208, 104, 114},
	title        = {154, 184, 234},
	status_bg    = {18, 22, 32},
	status_fg    = {146, 156, 176},
	input_bg     = {16, 20, 28},
	user_fg      = {164, 194, 244},
	user_bg      = {18, 22, 34},
	assistant_fg = {214, 218, 228},
	code_bg      = {18, 22, 32},
}

ROSE :: Theme{
	name         = "rose",
	bg           = {16, 10, 14},
	fg           = {234, 214, 224},
	muted        = {136, 106, 120},
	border       = {72, 44, 58},
	accent       = {214, 114, 154},
	accent_dim   = {146, 66, 96},
	highlight_bg = {32, 20, 28},
	highlight_fg = {248, 224, 234},
	warn         = {214, 154, 94},
	ok           = {144, 174, 124},
	error        = {208, 94, 104},
	title        = {234, 154, 184},
	status_bg    = {24, 14, 20},
	status_fg    = {176, 146, 160},
	input_bg     = {20, 12, 16},
	user_fg      = {234, 174, 204},
	user_bg      = {24, 14, 20},
	assistant_fg = {234, 214, 224},
	code_bg      = {22, 12, 18},
}

MONO :: Theme{
	name         = "mono",
	bg           = {10, 10, 10},
	fg           = {224, 224, 224},
	muted        = {116, 116, 116},
	border       = {52, 52, 52},
	accent       = {204, 204, 204},
	accent_dim   = {136, 136, 136},
	highlight_bg = {28, 28, 28},
	highlight_fg = {244, 244, 244},
	warn         = {184, 184, 184},
	ok           = {174, 174, 174},
	error        = {164, 164, 164},
	title        = {234, 234, 234},
	status_bg    = {18, 18, 18},
	status_fg    = {156, 156, 156},
	input_bg     = {16, 16, 16},
	user_fg      = {204, 204, 204},
	user_bg      = {18, 18, 18},
	assistant_fg = {224, 224, 224},
	code_bg      = {16, 16, 16},
}

DUSK :: Theme{
	name         = "dusk",
	bg           = {16, 12, 26},
	fg           = {224, 218, 234},
	muted        = {116, 106, 136},
	border       = {54, 44, 82},
	accent       = {164, 124, 214},
	accent_dim   = {106, 76, 156},
	highlight_bg = {28, 22, 44},
	highlight_fg = {240, 232, 248},
	warn         = {214, 164, 94},
	ok           = {124, 184, 154},
	error        = {208, 104, 124},
	title        = {194, 164, 234},
	status_bg    = {22, 16, 34},
	status_fg    = {156, 146, 176},
	input_bg     = {20, 14, 30},
	user_fg      = {184, 174, 234},
	user_bg      = {22, 16, 34},
	assistant_fg = {224, 218, 234},
	code_bg      = {20, 14, 32},
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
