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
