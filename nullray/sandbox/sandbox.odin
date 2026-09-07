/*
Sandbox entry: Landlock path control, seccomp-bpf, privacy scrub.
Apply before http/UI/threads.
*/

package sandbox

import "core:fmt"
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
	if cfg.mode == .Off {
		return Result{ok = true, applied = false, message = "sandbox off"}
	}

	ensure_dirs(cfg)

	g_state = {}
	g_state.mode = cfg.mode
	g_state.net = cfg.net
	g_state.fs = cfg.fs
	g_state.workspace = strings.clone(cfg.workspace)
	g_state.config_dir = strings.clone(cfg.config_dir)
	g_state.tmp_dir = strings.clone(cfg.tmp_dir)
	g_state.allow_rw = make([dynamic]string)
	g_state.allow_ro = make([dynamic]string)

	append_unique_path(&g_state.allow_rw, cfg.config_dir)
	append_unique_path(&g_state.allow_rw, cfg.tmp_dir)
	if cfg.fs == .RW {
		append_unique_path(&g_state.allow_rw, cfg.workspace)
	} else {
		append_unique_path(&g_state.allow_ro, cfg.workspace)
	}
	system_ro := []string{"/usr", "/lib", "/lib64", "/etc", "/etc/ssl", "/etc/ssl/certs", "/dev"}
	for p in system_ro {
		append_unique_path(&g_state.allow_ro, p)
	}
	for p in cfg.extra_ro {
		append_unique_path(&g_state.allow_ro, p)
	}
	for p in cfg.extra_rw {
		append_unique_path(&g_state.allow_rw, p)
	}

	when ODIN_OS == .Linux {
		msgs: [dynamic]string
		msgs = make([dynamic]string, context.temp_allocator)

		if cfg.privacy {
			env_scrub()
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
			}
		}

		return Result{
			ok = true,
			applied = g_state.applied,
			message = strings.join(msgs[:], ", ", context.temp_allocator),
		}
	} else {
		if cfg.mode == .Strict {
			return Result{ok = false, applied = false, message = "sandbox requires linux"}
		}
		return Result{ok = true, applied = false, message = "sandbox skipped (non-linux)"}
	}
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
	append(list, strings.clone(path))
}
