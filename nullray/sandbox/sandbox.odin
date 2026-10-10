// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Sandbox entry: Landlock path control, seccomp-bpf, privacy scrub.
Apply before http/UI/threads.
*/

package sandbox

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

g_state: State

state :: proc() -> ^State {
	return &g_state
}

Result :: struct {
	ok:      bool,
	applied: bool,
	message: string,
}

apply :: proc(cfg: Config) -> Result {
	// Global state outlives the caller's allocator, keep it on the heap so a
	// test tracking arena teardown cannot leave stale pointers behind.
	state_destroy_heap(&g_state)
	if cfg.mode == .Off {
		g_state.mode = .Off
		g_state.net = cfg.net
		g_state.fs = cfg.fs
		g_state.workspace = strings.clone(cfg.workspace, runtime.heap_allocator())
		g_state.config_dir = strings.clone(cfg.config_dir, runtime.heap_allocator())
		g_state.tmp_dir = strings.clone(cfg.tmp_dir, runtime.heap_allocator())
		return Result{ok = true, applied = false, message = "sandbox off"}
	}

	ensure_dirs(cfg)

	g_state.mode = cfg.mode
	g_state.net = cfg.net
	g_state.fs = cfg.fs
	g_state.workspace = strings.clone(cfg.workspace, runtime.heap_allocator())
	g_state.config_dir = strings.clone(cfg.config_dir, runtime.heap_allocator())
	g_state.tmp_dir = strings.clone(cfg.tmp_dir, runtime.heap_allocator())
	g_state.allow_rw = make([dynamic]string, 0, runtime.heap_allocator())
	g_state.allow_ro = make([dynamic]string, 0, runtime.heap_allocator())
	g_state.allow_sock = make([dynamic]string, 0, runtime.heap_allocator())
	g_state.ops_label = strings.clone(cfg.ops_label, runtime.heap_allocator())
	g_state.keep_docker_host = cfg.keep_docker_host
	g_state.keep_kubeconfig = cfg.keep_kubeconfig

	append_unique_path(&g_state.allow_rw, cfg.config_dir)
	append_unique_path(&g_state.allow_rw, cfg.tmp_dir)
	if cfg.fs == .RW {
		append_unique_path(&g_state.allow_rw, cfg.workspace)
	} else {
		append_unique_path(&g_state.allow_ro, cfg.workspace)
	}
	system_ro := []string{"/usr", "/lib", "/lib64", "/opt", "/nix", "/snap", "/home/linuxbrew", "/proc", "/sys", "/etc", "/etc/ssl", "/etc/ssl/certs", "/dev"}
	for p in system_ro {
		append_unique_path(&g_state.allow_ro, p)
	}
	for p in cfg.extra_ro {
		append_unique_path(&g_state.allow_ro, p)
	}
	for p in cfg.extra_rw {
		append_unique_path(&g_state.allow_rw, p)
	}
	for p in cfg.extra_sock {
		append_unique_path(&g_state.allow_sock, p)
		append_unique_path(&g_state.allow_ro, p)
	}

	when ODIN_OS == .Linux {
		msgs: [dynamic]string
		msgs = make([dynamic]string, context.temp_allocator)

		if cfg.privacy {
			env_scrub(cfg)
			append(&msgs, "privacy scrub")
		}

		if cfg.landlock {
			lok, lmsg := landlock_apply(cfg, &g_state)
			if !lok {
				if cfg.mode == .Strict {
					return Result{ok = false, applied = false, message = lmsg}
				}
				append(&msgs, fmt.tprintf("landlock warn: %s", lmsg))
			} else {
				append(&msgs, lmsg)
				g_state.applied = true
			}
		}

		if cfg.seccomp {
			sok, smsg := seccomp_apply()
			if !sok {
				if cfg.mode == .Strict {
					return Result{ok = false, applied = g_state.applied, message = smsg}
				}
				append(&msgs, fmt.tprintf("seccomp warn: %s", smsg))
			} else {
				append(&msgs, smsg)
				g_state.seccomp = strings.contains(smsg, "active")
			}
		}

		// Children spawned later inherit the process env. Git aborts hard
		// when it cannot read ~/.gitconfig or /etc/gitconfig under Landlock
		// ("fatal: unknown error occurred while reading the configuration
		// files"), so isolate config reads for every child we spawn.
		if g_state.applied {
			os.set_env("GIT_CONFIG_NOSYSTEM", "1")
			os.set_env("GIT_CONFIG_GLOBAL", "/dev/null")
			os.set_env("GIT_CONFIG_SYSTEM", "/dev/null")
			// Landlock grants only the sandbox tmp dir, so children that
			// honor TMPDIR (libc temp files, Bun, python tempfile) would
			// hit EACCES on bare /tmp. Pin it once so every spawned child
			// inherits a writable temp root.
			if len(cfg.tmp_dir) > 0 {
				os.set_env("TMPDIR", cfg.tmp_dir)
			}
		}
		return Result{
			ok = true,
			applied = g_state.applied,
			message = strings.join(msgs[:], ", ", context.temp_allocator),
		}
	} else when ODIN_OS == .Windows {
		wres := windows_job_apply(cfg, &g_state)
		if wres.ok && wres.applied {
			g_state.applied = true
			return wres
		}
		if cfg.mode == .Strict {
			return wres
		}
		return Result{ok = true, applied = false, message = "sandbox warn: Windows Job Object isolation unavailable"}
	} else {
		if cfg.mode == .Strict {
			return Result{ok = false, applied = false, message = "strict sandbox is unavailable on this OS. Use NULLRAY_SANDBOX=warn or off"}
		}
		return Result{ok = true, applied = false, message = "sandbox skipped (unsupported OS)"}
	}
}

/*
Shell output carrying a permission failure usually means Landlock denied
an exec or write on a path outside the grants. Return a one-line hint so
the model can route around the grant instead of probing blind; "" when
the sandbox is off or the text is clean.
*/
exec_denied_hint :: proc(text: string, allocator := context.allocator) -> string {
	if st := state(); st == nil || !st.applied {
		return ""
	}
	lower := strings.to_lower(text, context.temp_allocator)
	if !strings.contains(lower, "permission denied") &&
	   !strings.contains(lower, "operation not permitted") {
		return ""
	}
	return strings.clone(
		"note: nullray sandbox (landlock) may have blocked this path; grant it with NULLRAY_SANDBOX_EXTRA_RO or NULLRAY_SANDBOX_EXTRA_RW, or run with NULLRAY_SANDBOX=off",
		allocator,
	)
}

@(private)
append_unique_path :: proc(list: ^[dynamic]string, path: string) {
	if len(path) == 0 {
		return
	}
	for existing in list {
		if existing == path {
			return
		}
	}
	append(list, strings.clone(path, runtime.heap_allocator()))
}
