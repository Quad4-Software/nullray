// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build windows
/*
Socket conn I/O stub. nullray serve is unix-only, conn 0 writes to
stdout and never reaches these.
*/

package acp

conn_fd_write :: proc(fd: int, data: []u8) -> int {
	return -1
}

conn_fd_read :: proc(fd: int, buf: []u8) -> int {
	return -1
}

conn_fd_close :: proc(fd: int) {
}
