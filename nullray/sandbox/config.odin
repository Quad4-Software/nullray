/*
Sandbox mode, path allowlists, and privacy env parsing.
*/

package sandbox

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

Mode :: enum {
	Off,
	Warn,
	Strict,
}

Net_Mode :: enum {
	Off,
	Local,
	Full,
}

FS_Mode :: enum {
	RW,
	RO,
}

Config :: struct {
	mode:           Mode,
	net:            Net_Mode,
	fs:             FS_Mode,
	privacy:        bool,
	workspace:      string,
	config_dir:     string,
	tmp_dir:        string,
	extra_ro:       [dynamic]string,
	extra_rw:       [dynamic]string,
	seccomp:        bool,
	landlock:       bool,
}

State :: struct {
	applied:    bool,
	abi:        int,
	workspace:  string,
	config_dir: string,
	tmp_dir:    string,
	allow_rw:   [dynamic]string,
	allow_ro:   [dynamic]string,
	mode:       Mode,
	net:        Net_Mode,
	fs:         FS_Mode,
}

config_from_env :: proc(allocator := context.allocator) -> Config {
	cfg: Config
	cfg.mode = .Warn
	cfg.net = .Full
	cfg.fs = .RW
	cfg.privacy = true
	cfg.landlock = true
	cfg.seccomp = true
	cfg.extra_ro = make([dynamic]string, allocator)
	cfg.extra_rw = make([dynamic]string, allocator)

	if v, ok := os.lookup_env(constants.ENV_SANDBOX, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "off", "0", "false", "no":
			cfg.mode = .Off
		case "warn":
			cfg.mode = .Warn
		case "strict", "on", "1", "true", "yes":
			cfg.mode = .Strict
		}
	}
	if v, ok := os.lookup_env(constants.ENV_SANDBOX_NET, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "off", "0", "none":
			cfg.net = .Off
		case "local", "loopback":
			cfg.net = .Local
		case "full", "all":
			cfg.net = .Full
		}
	}
	if v, ok := os.lookup_env(constants.ENV_SANDBOX_FS, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "ro", "readonly", "read-only":
			cfg.fs = .RO
		case "rw", "readwrite", "read-write":
			cfg.fs = .RW
		}
	}
	if v, ok := os.lookup_env(constants.ENV_PRIVACY, context.temp_allocator); ok {
		cfg.privacy = !(v == "0" || v == "false" || v == "off")
	}
	if v, ok := os.lookup_env(constants.ENV_SECCOMP, context.temp_allocator); ok {
		cfg.seccomp = !(v == "0" || v == "false" || v == "off")
	}
	if v, ok := os.lookup_env(constants.ENV_LANDLOCK, context.temp_allocator); ok {
		cfg.landlock = !(v == "0" || v == "false" || v == "off")
	}

	if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
		cfg.workspace = strings.clone(v, allocator)
	} else if cwd, err := os.get_working_directory(allocator); err == nil {
		cfg.workspace = cwd
	} else {
		cfg.workspace = strings.clone(".", allocator)
	}

	cfg.config_dir = resolve_config_dir(allocator)
	cfg.tmp_dir = resolve_tmp_dir(allocator)
	return cfg
}

config_destroy :: proc(cfg: ^Config) {
	delete(cfg.workspace)
	delete(cfg.config_dir)
	delete(cfg.tmp_dir)
	for p in cfg.extra_ro {
		delete(p)
	}
	delete(cfg.extra_ro)
	for p in cfg.extra_rw {
		delete(p)
	}
	delete(cfg.extra_rw)
	cfg^ = {}
}

state_destroy :: proc(s: ^State) {
	delete(s.workspace)
	delete(s.config_dir)
	delete(s.tmp_dir)
	for p in s.allow_rw {
		delete(p)
	}
	delete(s.allow_rw)
	for p in s.allow_ro {
		delete(p)
	}
	delete(s.allow_ro)
	s^ = {}
}

resolve_config_dir :: proc(allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		if appdata, ok := os.lookup_env("APPDATA", context.temp_allocator); ok && len(appdata) > 0 {
			if joined, jerr := filepath.join({appdata, constants.CONFIG_DIR_NAME}, allocator); jerr == nil {
				return joined
			}
		}
		if home, hok := os.lookup_env("USERPROFILE", context.temp_allocator); hok && len(home) > 0 {
			if joined, jerr := filepath.join({home, ".config", constants.CONFIG_DIR_NAME}, allocator); jerr == nil {
				return joined
			}
		}
		if local, lok := os.lookup_env("LOCALAPPDATA", context.temp_allocator); lok && len(local) > 0 {
			if joined, jerr := filepath.join({local, "Temp", "nullray-config"}, allocator); jerr == nil {
				return joined
			}
		}
		return strings.clone(`C:\Temp\nullray-config`, allocator)
	} else {
		if xdg, ok := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator); ok && len(xdg) > 0 {
			if joined, jerr := filepath.join({xdg, constants.CONFIG_DIR_NAME}, allocator); jerr == nil {
				return joined
			}
		}
		home, hok := os.lookup_env("HOME", context.temp_allocator)
		if hok {
			if joined, jerr := filepath.join({home, ".config", constants.CONFIG_DIR_NAME}, allocator); jerr == nil {
				return joined
			}
		}
		if joined, jerr := filepath.join({"/tmp", "nullray-config"}, allocator); jerr == nil {
			return joined
		}
		return strings.clone("/tmp/nullray-config", allocator)
	}
}

resolve_tmp_dir :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_TMPDIR, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	when ODIN_OS == .Windows {
		if local, ok := os.lookup_env("LOCALAPPDATA", context.temp_allocator); ok && len(local) > 0 {
			if joined, jerr := filepath.join({local, "Temp", "nullray"}, allocator); jerr == nil {
				return joined
			}
		}
		if tmp, tok := os.lookup_env("TEMP", context.temp_allocator); tok && len(tmp) > 0 {
			if joined, jerr := filepath.join({tmp, "nullray"}, allocator); jerr == nil {
				return joined
			}
		}
		return strings.clone(`C:\Temp\nullray`, allocator)
	} else {
		if xdg, ok := os.lookup_env("XDG_RUNTIME_DIR", context.temp_allocator); ok && len(xdg) > 0 {
			if joined, jerr := filepath.join({xdg, "nullray"}, allocator); jerr == nil {
				return joined
			}
		}
		uid := os.get_uid()
		return fmt.aprintf("/tmp/nullray-%d", uid, allocator = allocator)
	}
}

ensure_dirs :: proc(cfg: Config) -> bool {
	_ = os.make_directory_all(cfg.config_dir)
	_ = os.make_directory_all(cfg.tmp_dir)
	return true
}

// True when subprocess execution is permitted under current sandbox policy.
shell_allowed :: proc(s: ^State) -> bool {
	if s == nil || !s.applied || s.mode == .Off {
		return true
	}
	return s.fs == .RW
}

// True if abs_path is under one of the allowlisted roots.
path_allowed :: proc(s: ^State, abs_path: string, want_write: bool) -> bool {
	if path_is_secret_blocked(abs_path) {
		return false
	}
	if s == nil || !s.applied {
		return true
	}
	clean, _ := filepath.clean(abs_path, context.temp_allocator)
	if want_write {
		for root in s.allow_rw {
			if path_beneath(clean, root) {
				return true
			}
		}
		return false
	}
	for root in s.allow_rw {
		if path_beneath(clean, root) {
			return true
		}
	}
	for root in s.allow_ro {
		if path_beneath(clean, root) {
			return true
		}
	}
	return false
}

path_beneath :: proc(path, root: string) -> bool {
	if path == root {
		return true
	}
	prefix := root
	if !strings.has_suffix(prefix, "/") {
		prefix = strings.concatenate({root, "/"}, context.temp_allocator)
	}
	return strings.has_prefix(path, prefix)
}
