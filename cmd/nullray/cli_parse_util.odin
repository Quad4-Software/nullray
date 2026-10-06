// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
CLI parse helpers: integer parse (no strconv dependency for flags) and the
next-arg value taker shared by flag cases.
*/

package main

@(private)
parse_cli_int :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 {
		return 0, false
	}
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}

take_value :: proc(args: []string, i: ^int) -> (string, bool) {
	if i^ + 1 >= len(args) {
		return "", false
	}
	i^ += 1
	return args[i^], true
}
