// SPDX-License-Identifier: 0BSD
/*
Line-block fuzzy match via Dice coefficient on normalized lines.
*/

package patch

import "core:strings"

FUZZY_MIN_SCORE :: 0.84
FUZZY_GAP :: 0.08

dice_bigrams :: proc(a, b: string) -> f64 {
	if len(a) == 0 && len(b) == 0 {
		return 1.0
	}
	if len(a) < 2 && len(b) < 2 {
		if a == b {
			return 1.0
		}
		return 0.0
	}
	if len(a) < 2 || len(b) < 2 {
		return 0.0
	}
	na := len(a) - 1
	nb := len(b) - 1
	counts := make(map[string]int, context.temp_allocator)
	for i in 0 ..< na {
		bg := a[i:i + 2]
		counts[bg] = counts[bg] + 1
	}
	overlap := 0
	for i in 0 ..< nb {
		bg := b[i:i + 2]
		if counts[bg] > 0 {
			overlap += 1
			counts[bg] -= 1
		}
	}
	return (2.0 * f64(overlap)) / f64(na + nb)
}

line_window_score :: proc(needle_lines, hay_lines: []string, start: int) -> f64 {
	n := len(needle_lines)
	if start < 0 || start + n > len(hay_lines) || n == 0 {
		return 0.0
	}
	sum: f64 = 0
	for i in 0 ..< n {
		sum += dice_bigrams(needle_lines[i], hay_lines[start + i])
	}
	return sum / f64(n)
}

Fuzzy_Hit :: struct {
	start_line: int,
	end_line:   int,
	score:      f64,
}

/*
Find best fuzzy line window for needle inside hay.
*/
fuzzy_find :: proc(hay, needle: string) -> (hit: Fuzzy_Hit, kind: Match_Kind) {
	norm_hay := normalize_for_compare(hay, context.temp_allocator)
	norm_needle := normalize_for_compare(needle, context.temp_allocator)
	if len(strings.trim_space(norm_needle)) == 0 {
		return {}, .None
	}

	hay_lines := strings.split_lines(norm_hay, context.temp_allocator)
	needle_lines := strings.split_lines(norm_needle, context.temp_allocator)
	n := len(needle_lines)
	if n == 0 || len(hay_lines) < n {
		return {}, .None
	}
	if len(needle_lines) > 0 && len(needle_lines[n - 1]) == 0 && strings.has_suffix(norm_needle, "\n") {
		needle_lines = needle_lines[:n - 1]
		n = len(needle_lines)
		if n == 0 || len(hay_lines) < n {
			return {}, .None
		}
	}

	best_score: f64 = -1
	second_score: f64 = -1
	best_start := -1
	for start in 0 ..= (len(hay_lines) - n) {
		sc := line_window_score(needle_lines, hay_lines, start)
		if sc > best_score {
			second_score = best_score
			best_score = sc
			best_start = start
		} else if sc > second_score {
			second_score = sc
		}
	}

	if best_start < 0 || best_score < FUZZY_MIN_SCORE {
		return {}, .None
	}
	if second_score >= 0 && (best_score - second_score) < FUZZY_GAP {
		return Fuzzy_Hit{start_line = best_start, end_line = best_start + n, score = best_score}, .Ambiguous
	}
	return Fuzzy_Hit{start_line = best_start, end_line = best_start + n, score = best_score}, .Fuzzy
}
