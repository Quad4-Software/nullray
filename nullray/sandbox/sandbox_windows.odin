// SPDX-License-Identifier: 0BSD
#+build windows

package sandbox

windows_job_apply :: proc(cfg: Config, state: ^State) -> Result {
	_ = cfg
	_ = state
	return Result{
		ok = false,
		applied = false,
		message = "Windows Job Object sandbox is not available in this build. Use NULLRAY_SANDBOX=warn or off, or rebuild with the Job Object spawn helper",
	}
}

windows_job_spawn_helper :: proc() -> (available: bool, message: string) {
	return false, "Job Object spawn helper stub"
}

landlock_apply :: proc(cfg: Config, state: ^State) -> (ok: bool, msg: string) {
	_ = cfg
	_ = state
	return false, "landlock is Linux-only"
}

seccomp_apply :: proc() -> (ok: bool, msg: string) {
	return false, "seccomp is Linux-only"
}
