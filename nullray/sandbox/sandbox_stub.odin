// SPDX-License-Identifier: 0BSD
#+build darwin, freebsd, netbsd, openbsd

package sandbox

landlock_apply :: proc(cfg: Config, state: ^State) -> (ok: bool, msg: string) {
	_ = cfg
	_ = state
	return false, "landlock requires linux"
}

seccomp_apply :: proc() -> (ok: bool, msg: string) {
	return false, "seccomp requires linux"
}
