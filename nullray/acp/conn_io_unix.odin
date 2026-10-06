// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows
/*
Socket fd write/read for serve conns. NOSIGNAL keeps a closed peer from
raising SIGPIPE in the daemon. POSIX only; windows has a stub.
*/

package acp

import c "core:c"
import "core:sys/posix"

conn_fd_write :: proc(fd: int, data: []u8) -> int {
	total: uint = 0
	for total < len(data) {
		n := posix.send(posix.FD(fd), raw_data(data[total:]), c.size_t(len(data) - total), {.NOSIGNAL})
		if n <= 0 {
			if posix.errno() == .EINTR {
				continue
			}
			return total > 0 ? int(total) : -1
		}
		total += uint(n)
	}
	return int(total)
}

conn_fd_read :: proc(fd: int, buf: []u8) -> int {
	for {
		n := posix.read(posix.FD(fd), raw_data(buf), c.size_t(uint(len(buf))))
		if n < 0 && posix.errno() == .EINTR {
			continue
		}
		return int(n)
	}
}

conn_fd_close :: proc(fd: int) {
	_ = posix.close(posix.FD(fd))
}
