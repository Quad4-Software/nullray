// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
RGB colors and ANSI palette mapping.
*/

package ui

Color :: struct {
	r, g, b: u8,
}

Color_Mode :: enum {
	None,
	Ansi16,
	Ansi256,
	Truecolor,
}

rgb :: proc(r, g, b: u8) -> Color {
	return Color{r, g, b}
}

// Parse #rgb, #rrggbb, rgb(r,g,b), or named colors. ok=false leaves c unchanged.
color_parse :: proc(s: string) -> (c: Color, ok: bool) {
	raw := s
	// trim manually to avoid extra imports churn in hot path
	for len(raw) > 0 && (raw[0] == ' ' || raw[0] == '\t') {
		raw = raw[1:]
	}
	for len(raw) > 0 && (raw[len(raw) - 1] == ' ' || raw[len(raw) - 1] == '\t') {
		raw = raw[:len(raw) - 1]
	}
	if len(raw) == 0 {
		return {}, false
	}
	// named
	switch raw {
	case "red":
		return Color{220, 80, 80}, true
	case "green":
		return Color{80, 180, 100}, true
	case "blue":
		return Color{80, 140, 220}, true
	case "yellow":
		return Color{220, 200, 80}, true
	case "cyan":
		return Color{80, 200, 200}, true
	case "magenta", "purple":
		return Color{180, 100, 200}, true
	case "white":
		return Color{240, 240, 240}, true
	case "black":
		return Color{16, 16, 16}, true
	case "orange":
		return Color{230, 140, 60}, true
	case "gray", "grey":
		return Color{128, 128, 128}, true
	}
	// #rgb or #rrggbb
	if raw[0] == '#' {
		hex := raw[1:]
		if len(hex) == 3 {
			r := hex_nibble(hex[0])
			g := hex_nibble(hex[1])
			b := hex_nibble(hex[2])
			if r < 0 || g < 0 || b < 0 {
				return {}, false
			}
			return Color{u8(r * 17), u8(g * 17), u8(b * 17)}, true
		}
		if len(hex) == 6 {
			r := hex_byte(hex[0:2])
			g := hex_byte(hex[2:4])
			b := hex_byte(hex[4:6])
			if r < 0 || g < 0 || b < 0 {
				return {}, false
			}
			return Color{u8(r), u8(g), u8(b)}, true
		}
		return {}, false
	}
	// rgb(r,g,b)
	if len(raw) > 4 && (raw[0] == 'r' || raw[0] == 'R') {
		// crude parse
		inner := raw
		// find (
		lp := -1
		rp := -1
		for i in 0 ..< len(inner) {
			if inner[i] == '(' {
				lp = i
			}
			if inner[i] == ')' {
				rp = i
			}
		}
		if lp >= 0 && rp > lp {
			parts := inner[lp + 1:rp]
			r, g, b, pok := parse_rgb_triple(parts)
			if pok {
				return Color{r, g, b}, true
			}
		}
	}
	return {}, false
}

@(private)
hex_nibble :: proc(c: u8) -> int {
	switch c {
	case '0' ..= '9':
		return int(c - '0')
	case 'a' ..= 'f':
		return int(c - 'a' + 10)
	case 'A' ..= 'F':
		return int(c - 'A' + 10)
	}
	return -1
}

@(private)
hex_byte :: proc(s: string) -> int {
	if len(s) != 2 {
		return -1
	}
	hi := hex_nibble(s[0])
	lo := hex_nibble(s[1])
	if hi < 0 || lo < 0 {
		return -1
	}
	return hi * 16 + lo
}

@(private)
parse_rgb_triple :: proc(s: string) -> (r, g, b: u8, ok: bool) {
	// split on comma
	vals: [3]int
	vi := 0
	n := 0
	neg := false
	for i := 0; i <= len(s); i += 1 {
		c: u8 = 0
		if i < len(s) {
			c = s[i]
		}
		if c >= '0' && c <= '9' {
			n = n * 10 + int(c - '0')
			if n > 255 {
				n = 255
			}
			continue
		}
		if c == '-' {
			neg = true
			continue
		}
		// separator or end
		if c == ',' || i == len(s) {
			if neg {
				n = 0
			}
			if vi < 3 {
				vals[vi] = n
				vi += 1
			}
			n = 0
			neg = false
			continue
		}
		// skip spaces
		if c == ' ' || c == '\t' {
			continue
		}
	}
	if vi < 3 {
		return 0, 0, 0, false
	}
	return u8(vals[0]), u8(vals[1]), u8(vals[2]), true
}

lerp_u8 :: proc(a, b: u8, t: f32) -> u8 {
	af := f32(a)
	bf := f32(b)
	v := af + (bf - af) * t
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return u8(v)
}

color_lerp :: proc(a, b: Color, t: f32) -> Color {
	tt := t
	if tt < 0 {
		tt = 0
	} else if tt > 1 {
		tt = 1
	}
	return Color{
		r = lerp_u8(a.r, b.r, tt),
		g = lerp_u8(a.g, b.g, tt),
		b = lerp_u8(a.b, b.b, tt),
	}
}

// h is degrees (wrapped), s and v are 0..1.
color_from_hsv :: proc(h, s, v: f32) -> Color {
	hh := h
	for hh < 0 {
		hh += 360
	}
	for hh >= 360 {
		hh -= 360
	}
	ss := s
	if ss < 0 {
		ss = 0
	} else if ss > 1 {
		ss = 1
	}
	vv := v
	if vv < 0 {
		vv = 0
	} else if vv > 1 {
		vv = 1
	}
	if ss <= 0 {
		c := u8(vv * 255 + 0.5)
		return Color{c, c, c}
	}
	sector := hh / 60
	i := int(sector)
	f := sector - f32(i)
	p := vv * (1 - ss)
	q := vv * (1 - ss * f)
	t := vv * (1 - ss * (1 - f))
	r, g, b: f32
	switch i % 6 {
	case 0:
		r, g, b = vv, t, p
	case 1:
		r, g, b = q, vv, p
	case 2:
		r, g, b = p, vv, t
	case 3:
		r, g, b = p, q, vv
	case 4:
		r, g, b = t, p, vv
	case:
		r, g, b = vv, p, q
	}
	return Color{
		r = u8(r * 255 + 0.5),
		g = u8(g * 255 + 0.5),
		b = u8(b * 255 + 0.5),
	}
}

// Smooth rainbow letter color. phase is 0..1 over one full cycle.
// letter_i and letter_n space hues across the word so it reads as a gradient.
brand_letter_color :: proc(letter_i, letter_n: int, phase: f32, base: Color = {}) -> Color {
	n := max(1, letter_n)
	i := letter_i
	if i < 0 {
		i = 0
	}
	// Spread ~140 deg across the word; spin the whole band with phase.
	spread := 140.0 / f32(n)
	hue := phase * 360 + f32(i) * spread
	// Soft pastel; mono themes still get chroma so the brand stays lively.
	sat: f32 = 0.62
	val: f32 = 0.92
	c := color_from_hsv(hue, sat, val)
	if base.r != 0 || base.g != 0 || base.b != 0 {
		// Nudge toward the theme title color so ink/ember stay familiar.
		c = color_lerp(c, base, 0.28)
	}
	return c
}

color_to_ansi16 :: proc(c: Color) -> int {
	levels := [8]Color{
		{0, 0, 0},
		{170, 0, 0},
		{0, 170, 0},
		{170, 85, 0},
		{0, 0, 170},
		{170, 0, 170},
		{0, 170, 170},
		{170, 170, 170},
	}
	bright := [8]Color{
		{85, 85, 85},
		{255, 85, 85},
		{85, 255, 85},
		{255, 255, 85},
		{85, 85, 255},
		{255, 85, 255},
		{85, 255, 255},
		{255, 255, 255},
	}
	best := 0
	best_d := 1 << 30
	for i in 0 ..< 8 {
		d := color_dist2(c, levels[i])
		if d < best_d {
			best_d = d
			best = i
		}
		d = color_dist2(c, bright[i])
		if d < best_d {
			best_d = d
			best = 8 + i
		}
	}
	return best
}

color_to_ansi256 :: proc(c: Color) -> int {
	if c.r == c.g && c.g == c.b {
		if c.r < 8 {
			return 16
		}
		if c.r > 248 {
			return 231
		}
		return 232 + int((int(c.r) - 8) * 24 / 247)
	}
	ri := int(c.r) * 5 / 255
	gi := int(c.g) * 5 / 255
	bi := int(c.b) * 5 / 255
	return 16 + 36 * ri + 6 * gi + bi
}

@(private)
color_dist2 :: proc(a, b: Color) -> int {
	dr := int(a.r) - int(b.r)
	dg := int(a.g) - int(b.g)
	db := int(a.b) - int(b.b)
	return dr * dr + dg * dg + db * db
}
