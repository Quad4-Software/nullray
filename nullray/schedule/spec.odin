// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Schedule spec parsing and next-fire math. Pure functions over unix seconds so
the whole grammar is unit-testable without threads or wall clock access.

Grammar:
  in <dur>        one-shot relative delay
  every <dur>     fixed interval
  at HH:MM        next daily wall-clock occurrence
  m h dom mon dow 5-field cron fields: star, star/n steps, a-b ranges, a,b lists
<dur> is one or more <int><s|m|h|d> pairs, e.g. 90s, 30m, 1h30m, 7d.
*/

package schedule

import "core:strconv"
import "core:strings"

@(private)
CRON_MAX_DAYS :: 8 * 366

Cron_Field :: struct {
	mask: u64,
	any:  bool,
}

Cron :: struct {
	min:  Cron_Field,
	hour: Cron_Field,
	dom:  Cron_Field,
	mon:  Cron_Field,
	dow:  Cron_Field,
}

@(private)
field_bit :: proc(f: Cron_Field, v: int) -> bool {
	if v < 0 || v > 63 {
		return false
	}
	return (f.mask >> u64(v)) & 1 == 1
}

// Floored modulo for non-negative divisors, safe on negative inputs.
@(private)
floor_mod :: proc(a: i64, b: i64) -> i64 {
	r := a % b
	if r < 0 {
		r += b
	}
	return r
}

// Howard Hinnant days-from-civil. Returns days since 1970-01-01.
days_from_civil :: proc(y, m, d: int) -> i64 {
	yy := y
	if m <= 2 {
		yy -= 1
	}
	era := (yy >= 0 ? yy : yy - 399) / 400
	yoe := yy - era * 400
	mp := (m + 9) % 12
	doy := (153 * mp + 2) / 5 + d - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return i64(era*146097 + doe - 719468)
}

civil_from_days :: proc(z: i64) -> (y, m, d: int) {
	zz := z + 719468
	era := (zz >= 0 ? zz : zz - 146096) / 146097
	doe := int(zz - era * 146097)
	yoe := (doe - doe/1460 + doe/36524 - doe/146096) / 365
	yy := yoe + int(era) * 400
	doy := doe - (365*yoe + yoe/4 - yoe/100)
	mp := (5*doy + 2) / 153
	dd := doy - (153*mp+2)/5 + 1
	mm := mp + (mp < 10 ? 3 : -9)
	return yy + (mm <= 2 ? 1 : 0), mm, dd
}

// 0 = Sunday. 1970-01-01 (day 0) was a Thursday.
weekday_from_days :: proc(z: i64) -> int {
	return int(floor_mod(z + 4, 7))
}

// Parses "90s" "30m" "1h30m" "7d" into seconds.
dur_parse :: proc(text: string) -> (sec: i64, ok: bool) {
	s := strings.trim_space(text)
	if len(s) == 0 {
		return 0, false
	}
	i := 0
	total: i64 = 0
	for i < len(s) {
		j := i
		for j < len(s) && s[j] >= '0' && s[j] <= '9' {
			j += 1
		}
		if j == i {
			return 0, false
		}
		n, n_ok := strconv.parse_i64(s[i:j])
		if !n_ok {
			return 0, false
		}
		if j >= len(s) {
			return 0, false
		}
		mult: i64
		switch s[j] {
		case 's':
			mult = 1
		case 'm':
			mult = 60
		case 'h':
			mult = 3600
		case 'd':
			mult = 86400
		case:
			return 0, false
		}
		// n*mult can overflow i64 on absurd counts; reject instead of
		// wrapping into a negative or tiny duration.
		if n > (max(i64) - total) / mult {
			return 0, false
		}
		total += n * mult
		i = j + 1
	}
	return total, total > 0
}

@(private)
cron_parse_field :: proc(text: string, lo, hi: int) -> (field: Cron_Field, ok: bool) {
	if len(text) == 0 {
		return {}, false
	}
	if text == "*" {
		mask: u64 = 0
		for v in lo ..= hi {
			mask |= u64(1) << u64(v)
		}
		return Cron_Field{mask = mask, any = true}, true
	}
	mask: u64 = 0
	parts := strings.split(text, ",", context.temp_allocator)
	for part in parts {
		p := strings.trim_space(part)
		if len(p) == 0 {
			return {}, false
		}
		step := 1
		base := p
		if slash := strings.index_byte(p, '/'); slash >= 0 {
			base = p[:slash]
			n, n_ok := strconv.parse_int(p[slash + 1:])
			if !n_ok || n <= 0 {
				return {}, false
			}
			step = n
		}
		blo, bhi := lo, hi
		if base == "*" {
			// */n form
		} else if dash := strings.index_byte(base, '-'); dash >= 0 {
			a, a_ok := strconv.parse_int(base[:dash])
			b, b_ok := strconv.parse_int(base[dash + 1:])
			if !a_ok || !b_ok || a > b {
				return {}, false
			}
			blo, bhi = a, b
		} else {
			a, a_ok := strconv.parse_int(base)
			if !a_ok {
				return {}, false
			}
			blo, bhi = a, a
			if step > 1 {
				bhi = hi
			}
		}
		if blo < lo || bhi > hi {
			return {}, false
		}
		for v := blo; v <= bhi; v += step {
			mask |= u64(1) << u64(v)
		}
	}
	return Cron_Field{mask = mask}, mask != 0
}

cron_parse :: proc(spec: string) -> (c: Cron, ok: bool) {
	fields := strings.fields(strings.trim_space(spec), context.temp_allocator)
	if len(fields) != 5 {
		return {}, false
	}
	c.min, ok = cron_parse_field(fields[0], 0, 59)
	if !ok {
		return {}, false
	}
	c.hour, ok = cron_parse_field(fields[1], 0, 23)
	if !ok {
		return {}, false
	}
	c.dom, ok = cron_parse_field(fields[2], 1, 31)
	if !ok {
		return {}, false
	}
	c.mon, ok = cron_parse_field(fields[3], 1, 12)
	if !ok {
		return {}, false
	}
	// dow range is 0-7 with 7 as a Sunday alias for 0, per cron convention.
	c.dow, ok = cron_parse_field(fields[4], 0, 7)
	if !ok {
		return {}, false
	}
	if field_bit(c.dow, 7) {
		c.dow.mask = (c.dow.mask &~ (u64(1) << 7)) | u64(1)
	}
	return c, true
}

// First minute boundary strictly after now whose fields all match.
@(private)
cron_next :: proc(c: Cron, now: i64) -> (i64, bool) {
	first := ((now / 60) + 1) * 60
	day0 := first / 86400
	for di in 0 ..< CRON_MAX_DAYS {
		day := day0 + i64(di)
		y, mo, d := civil_from_days(day)
		_ = y
		if !field_bit(c.mon, mo) {
			continue
		}
		day_ok: bool
		if c.dom.any && c.dow.any {
			day_ok = true
		} else if c.dom.any {
			day_ok = field_bit(c.dow, weekday_from_days(day))
		} else if c.dow.any {
			day_ok = field_bit(c.dom, d)
		} else {
			day_ok = field_bit(c.dom, d) || field_bit(c.dow, weekday_from_days(day))
		}
		if !day_ok {
			continue
		}
		base := day * 86400
		for h in 0 ..< 24 {
			if !field_bit(c.hour, h) {
				continue
			}
			for m in 0 ..< 60 {
				if !field_bit(c.min, m) {
					continue
				}
				cand := base + i64(h*3600 + m*60)
				if cand >= first {
					return cand, true
				}
			}
		}
	}
	return 0, false
}

// Next wall-clock HH:MM strictly after now.
@(private)
at_next :: proc(text: string, now: i64) -> (i64, bool) {
	colon := strings.index_byte(text, ':')
	if colon <= 0 {
		return 0, false
	}
	h, h_ok := strconv.parse_int(text[:colon])
	m, m_ok := strconv.parse_int(text[colon + 1:])
	if !h_ok || !m_ok || h < 0 || h > 23 || m < 0 || m > 59 {
		return 0, false
	}
	day := now / 86400
	cand := day*86400 + i64(h*3600+m*60)
	if cand <= now {
		cand += 86400
	}
	return cand, true
}

@(private)
spec_word :: proc(s, prefix: string) -> (rest: string, ok: bool) {
	if strings.has_prefix(s, prefix) {
		return strings.trim_space(s[len(prefix):]), true
	}
	return "", false
}

/*
Resolve the next fire time for a spec. For "in"/"every" the result is
now + interval, so callers anchor recurring jobs on the last fire time.
*/
spec_next_fire :: proc(spec: string, now: i64) -> (i64, bool) {
	s := strings.trim_space(spec)
	if rest, ok := spec_word(s, "in "); ok {
		if d, d_ok := dur_parse(rest); d_ok {
			return now + d, true
		}
		return 0, false
	}
	if rest, ok := spec_word(s, "every "); ok {
		if d, d_ok := dur_parse(rest); d_ok {
			return now + d, true
		}
		return 0, false
	}
	if rest, ok := spec_word(s, "at "); ok {
		return at_next(rest, now)
	}
	if c, ok := cron_parse(s); ok {
		return cron_next(c, now)
	}
	return 0, false
}

// Interval in seconds for "in"/"every" specs; cron has no fixed interval.
spec_interval_sec :: proc(spec: string) -> (i64, bool) {
	s := strings.trim_space(spec)
	if rest, ok := spec_word(s, "in "); ok {
		return dur_parse(rest)
	}
	if rest, ok := spec_word(s, "every "); ok {
		return dur_parse(rest)
	}
	return 0, false
}

spec_recurring :: proc(spec: string) -> bool {
	s := strings.trim_space(spec)
	if strings.has_prefix(s, "every ") {
		return true
	}
	if strings.has_prefix(s, "in ") || strings.has_prefix(s, "at ") {
		return false
	}
	_, ok := cron_parse(s)
	return ok
}
