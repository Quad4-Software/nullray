// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
//go:build windows

package main

// Windows has no SIGPIPE; writes fail with an error instead.
install_pipe_signals :: proc() {
}
