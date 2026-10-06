// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package schedule

import "core:testing"

// 2024-01-15 10:00:00 UTC, a Monday.
TEST_NOW :: i64(1705276800 + 36000)

@(test)
test_civil_anchor :: proc(t: ^testing.T) {
	testing.expect_value(t, days_from_civil(2024, 1, 15), i64(19737))
	testing.expect_value(t, weekday_from_days(19737), 1)
	y, m, d := civil_from_days(19737)
	testing.expect_value(t, y, 2024)
	testing.expect_value(t, m, 1)
	testing.expect_value(t, d, 15)
	leap := days_from_civil(2024, 2, 29)
	testing.expect_value(t, leap, i64(19782))
}

@(test)
test_dur_parse :: proc(t: ^testing.T) {
	cases := []struct {
		text: string,
		sec:  i64,
	}{
		{"10m", 600},
		{"90s", 90},
		{"1h", 3600},
		{"2d", 172800},
		{"1h30m", 5400},
		{"45s", 45},
	}
	for c in cases {
		sec, ok := dur_parse(c.text)
		testing.expect(t, ok, c.text)
		testing.expect_value(t, sec, c.sec)
	}
	bads := []string{"", "abc", "10", "10x", "0s", "-5m", "mm"}
	for bad in bads {
		_, ok := dur_parse(bad)
		testing.expect(t, !ok, bad)
	}
	// Overflow: each term parses as i64 but n*mult or the sum wraps.
	overflow := []string{
		"200000000000000000d",
		"99999999999999999h",
		"5000000000000000000s5000000000000000000s",
	}
	for bad in overflow {
		_, ok := dur_parse(bad)
		testing.expect(t, !ok, bad)
	}
}

@(test)
test_in_every_next_fire :: proc(t: ^testing.T) {
	cases := []struct {
		spec: string,
		at:   i64,
	}{
		{"in 10m", TEST_NOW + 600},
		{"every 30m", TEST_NOW + 1800},
		{"every 1h", TEST_NOW + 3600},
		{"every 90s", TEST_NOW + 90},
		{"every 1h30m", TEST_NOW + 5400},
	}
	for c in cases {
		got, ok := spec_next_fire(c.spec, TEST_NOW)
		testing.expect(t, ok, c.spec)
		testing.expect_value(t, got, c.at)
	}
}

@(test)
test_at_next_fire :: proc(t: ^testing.T) {
	got, ok := spec_next_fire("at 14:30", TEST_NOW)
	testing.expect(t, ok)
	testing.expect_value(t, got, TEST_NOW + 16200)
	got, ok = spec_next_fire("at 09:00", TEST_NOW)
	testing.expect(t, ok)
	testing.expect_value(t, got, TEST_NOW + 82800)
	_, ok = spec_next_fire("at 25:00", TEST_NOW)
	testing.expect(t, !ok)
}

@(test)
test_cron_next_fire :: proc(t: ^testing.T) {
	cases := []struct {
		spec: string,
		at:   i64,
	}{
		{"* * * * *", TEST_NOW + 60},
		{"0 * * * *", TEST_NOW + 3600},
		{"*/15 * * * *", TEST_NOW + 900},
		{"30 9 * * *", TEST_NOW + 84600},
		{"0 0 * * 1", TEST_NOW + 568800},
		// dow 7 is a Sunday alias for 0: next is 2024-01-21 00:00 UTC.
		{"0 0 * * 7", TEST_NOW + 482400},
		{"0 0 * * 0", TEST_NOW + 482400},
		{"0 0 * * 1-5", TEST_NOW + 50400},
		{"0,30 9-17 * * *", TEST_NOW + 1800},
		{"0 0 1 * *", i64(1706745600)},
		{"0 0 29 2 *", i64(1709164800)},
		{"0 0 15 * 1", i64(1705881600)},
	}
	for c in cases {
		got, ok := spec_next_fire(c.spec, TEST_NOW)
		testing.expect(t, ok, c.spec)
		testing.expect_value(t, got, c.at)
	}
}

@(test)
test_cron_bad_specs :: proc(t: ^testing.T) {
	bads := []string{
		"* * * *",
		"* * * * * *",
		"60 * * * *",
		"* 24 * * *",
		"x * * * *",
		"* * 0 * *",
		"* * * 13 *",
		"* * * * 8",
		"*/0 * * * *",
		"every xyz",
		"in",
		"",
	}
	for bad in bads {
		_, ok := spec_next_fire(bad, TEST_NOW)
		testing.expect(t, !ok, bad)
	}
}

@(test)
test_cron_off_minute_anchor :: proc(t: ^testing.T) {
	mid := TEST_NOW + 33
	got, ok := spec_next_fire("* * * * *", mid)
	testing.expect(t, ok)
	testing.expect_value(t, got, TEST_NOW + 60)
	got, ok = spec_next_fire("*/15 * * * *", mid)
	testing.expect(t, ok)
	testing.expect_value(t, got, TEST_NOW + 900)
}

@(test)
test_spec_flags :: proc(t: ^testing.T) {
	testing.expect(t, spec_recurring("every 30m"))
	testing.expect(t, spec_recurring("0 * * * *"))
	testing.expect(t, !spec_recurring("in 10m"))
	testing.expect(t, !spec_recurring("at 14:30"))
	ivl, ok := spec_interval_sec("every 30m")
	testing.expect(t, ok)
	testing.expect_value(t, ivl, i64(1800))
	_, ok = spec_interval_sec("0 * * * *")
	testing.expect(t, !ok)
}
