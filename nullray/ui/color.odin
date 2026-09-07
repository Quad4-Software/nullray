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
