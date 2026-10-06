// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build windows
/*
nullray serve needs unix domain sockets; stub for Windows builds.
*/

package serve

import "core:fmt"

sock_dir :: proc(allocator := context.allocator) -> string {
	return ""
}

sock_path :: proc(allocator := context.allocator) -> string {
	return ""
}

Prebind :: struct {
	fd:   int,
	path: string,
	err:  string,
}

prebind :: proc() -> Prebind {
	return Prebind{fd = -1, err = "unix sockets are not supported on windows"}
}

prebind_destroy :: proc(pb: ^Prebind) {
}

run_serve :: proc(listen_fd: int, path: string, bare: bool) -> int {
	fmt.eprintln("nullray serve: unix sockets are not supported on windows")
	return 1
}

run_attach :: proc(target: string) -> int {
	fmt.eprintln("nullray attach: unix sockets are not supported on windows")
	return 1
}

run_print_via_serve :: proc(prompt: string, cwd: string, timeout_sec: int) -> int {
	fmt.eprintln("nullray --connect: unix sockets are not supported on windows")
	return 2
}
