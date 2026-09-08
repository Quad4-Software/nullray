// SPDX-License-Identifier: 0BSD
/*
Crash dumps, debug logging, and doctor diagnostics.
*/

package crash

import "base:runtime"
import "core:debug/trace"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:store"
import "nullray:ui"

State :: struct {
	installed:  bool,
	debug:      bool,
	session_id: string,
	note:       string,
	dir:        string,
}

g: State

debug_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_DEBUG, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

/*
Install crash handlers and wire assertion failure dumps.
Call once at process start. Sets context.assertion_failure_proc on the caller.
*/
install :: proc() {
	g.debug = debug_from_env()
	if g.installed {
		context.assertion_failure_proc = assertion_failure_proc
		return
	}
	g.installed = true
	cfg := sandbox.resolve_config_dir(context.allocator)
	defer delete(cfg)
	dir, jerr := filepath.join({cfg, "crashes"}, context.allocator)
	if jerr != nil {
		dir = strings.clone("/tmp/nullray-crashes")
	}
	delete(g.dir)
	g.dir = dir
	_ = os.make_directory_all(g.dir)
	install_signals()
	context.assertion_failure_proc = assertion_failure_proc
	logf("crash helper installed, dumps in %s", g.dir)
}

set_session :: proc(session_id: string) {
	delete(g.session_id)
	g.session_id = ""
	if len(session_id) > 0 {
		g.session_id = strings.clone(session_id)
	}
}

set_note :: proc(note: string) {
	delete(g.note)
	g.note = ""
	if len(note) > 0 {
		g.note = strings.clone(note)
	}
}

enabled :: proc() -> bool {
	return g.debug
}

logf :: proc(format: string, args: ..any) {
	if !g.debug {
		return
	}
	fmt.eprintf("nullray: debug: ")
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

assertion_failure_proc :: proc(prefix, message: string, loc := #caller_location) -> ! {
	ui.term_emergency_restore()
	path := write_report("assert", prefix, message, loc)
	if len(path) > 0 {
		fmt.eprintln("nullray: crash report:", path)
		delete(path)
	}
	{
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		lines, err := trace.resolve(trace.capture(skip = 1), context.temp_allocator, context.temp_allocator)
		if err == nil {
			fmt.eprintln("[back trace]")
			trace.print(lines)
			trace.locations_destroy(lines, context.temp_allocator)
		}
	}
	runtime.default_assertion_failure_proc(prefix, message, loc)
}

/*
Write a crash report. Caller owns the returned path when non-empty.
*/
write_report :: proc(kind, prefix, message: string, loc: runtime.Source_Code_Location = {}) -> string {
	if len(g.dir) == 0 {
		return ""
	}
	_ = os.make_directory_all(g.dir)
	stamp := time.to_unix_seconds(time.now())
	name := fmt.tprintf("%s-%d.txt", kind, stamp)
	path, jerr := filepath.join({g.dir, name}, context.allocator)
	if jerr != nil {
		return ""
	}

	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	fmt.sbprintf(&b, "nullray crash report\n")
	fmt.sbprintf(&b, "version: %s\n", constants.VERSION)
	fmt.sbprintf(&b, "built: %s %s\n", constants.BUILD_DATE, constants.BUILD_TIME)
	fmt.sbprintf(&b, "os: %v arch: %v\n", ODIN_OS, ODIN_ARCH)
	fmt.sbprintf(&b, "kind: %s\n", kind)
	if len(prefix) > 0 {
		fmt.sbprintf(&b, "prefix: %s\n", prefix)
	}
	if len(message) > 0 {
		fmt.sbprintf(&b, "message: %s\n", message)
	}
	if loc.file_path != "" {
		fmt.sbprintf(&b, "location: %s:%d:%d %s\n", loc.file_path, loc.line, loc.column, loc.procedure)
	}
	if len(g.session_id) > 0 {
		fmt.sbprintf(&b, "session: %s\n", g.session_id)
	}
	if len(g.note) > 0 {
		fmt.sbprintf(&b, "note: %s\n", g.note)
	}
	if ws, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok {
		fmt.sbprintf(&b, "workspace: %s\n", ws)
	}
	if provider, ok := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator); ok {
		fmt.sbprintf(&b, "provider: %s\n", provider)
	}
	if model, ok := os.lookup_env(constants.ENV_MODEL, context.temp_allocator); ok {
		fmt.sbprintf(&b, "model: %s\n", model)
	}
	if sand, ok := os.lookup_env(constants.ENV_SANDBOX, context.temp_allocator); ok {
		fmt.sbprintf(&b, "sandbox: %s\n", sand)
	}
	sstate := sandbox.state()
	if sstate != nil {
		fmt.sbprintf(
			&b,
			"sandbox_state: applied=%v landlock_abi=%d net=%v seccomp=%v\n",
			sstate.applied,
			sstate.abi,
			sstate.net,
			sstate.seccomp,
		)
	}
	fmt.sbprintf(&b, "pid: %d\n", os.get_pid())
	fmt.sbprintf(&b, "\n--- backtrace ---\n")
	append_backtrace(&b)

	body := strings.to_string(b)
	if werr := os.write_entire_file(path, transmute([]u8)body); werr != nil {
		delete(path)
		return ""
	}
	return path
}

@(private)
append_backtrace :: proc(b: ^strings.Builder) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	lines, err := trace.resolve(trace.capture(skip = 2), context.temp_allocator, context.temp_allocator)
	if err != nil {
		fmt.sbprintf(b, "(backtrace unavailable: %v)\n", err)
		fmt.sbprintf(b, "hint: rebuild with make debug for symbols\n")
		return
	}
	defer trace.locations_destroy(lines, context.temp_allocator)
	for loc, i in lines {
		fmt.sbprintf(b, "#%d %s at %s", i, loc.procedure, loc.file_path)
		if loc.line > 0 {
			fmt.sbprintf(b, ":%d", loc.line)
			if loc.column > 0 {
				fmt.sbprintf(b, ":%d", loc.column)
			}
		}
		fmt.sbprintf(b, "\n")
	}
}

latest_report_path :: proc(allocator := context.allocator) -> string {
	if len(g.dir) == 0 {
		return ""
	}
	entries, err := os.read_all_directory_by_path(g.dir, context.temp_allocator)
	if err != nil {
		return ""
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	best_name := ""
	best_time: i64 = -1
	for e in entries {
		if e.type == .Directory {
			continue
		}
		if !strings.has_suffix(e.name, ".txt") {
			continue
		}
		mod := time.to_unix_seconds(e.modification_time)
		if mod >= best_time {
			best_time = mod
			best_name = e.name
		}
	}
	if len(best_name) == 0 {
		return ""
	}
	joined, jerr := filepath.join({g.dir, best_name}, allocator)
	if jerr != nil {
		return ""
	}
	return joined
}

/*
Print environment and recent crash dump paths for support.
*/
doctor :: proc() -> int {
	install()
	print_version_line()
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	fmt.printf("config: %s\n", cfg)
	fmt.printf("crashes: %s\n", g.dir)
	fmt.printf("debug: %v (NULLRAY_DEBUG or --debug)\n", g.debug)
	fmt.printf("os: %v arch: %v\n", ODIN_OS, ODIN_ARCH)
	sstate := sandbox.state()
	dcfg := sandbox.config_from_env()
	defer sandbox.config_destroy(&dcfg)
	fmt.printf("sandbox config: mode=%v net=%v fs=%v\n", dcfg.mode, dcfg.net, dcfg.fs)
	fmt.printf("sandbox extras: %s\n", sandbox.ops_summary_line(dcfg, context.temp_allocator))
	if len(dcfg.extra_rw) > 0 {
		fmt.printf("extra_rw: %s\n", strings.join(dcfg.extra_rw[:], ",", context.temp_allocator))
	}
	if len(dcfg.extra_ro) > 0 {
		fmt.printf("extra_ro: %s\n", strings.join(dcfg.extra_ro[:], ",", context.temp_allocator))
	}
	if len(dcfg.extra_sock) > 0 {
		fmt.printf("extra_sock: %s\n", strings.join(dcfg.extra_sock[:], ",", context.temp_allocator))
	}
	print_env("ops", constants.ENV_OPS)
	print_env("secrets_allow", constants.ENV_SECRETS_ALLOW)
	if sstate != nil && sstate.applied {
		fmt.printf(
			"sandbox state: applied=%v landlock_abi=%d net=%v seccomp=%v\n",
			sstate.applied,
			sstate.abi,
			sstate.net,
			sstate.seccomp,
		)
	} else {
		fmt.println("sandbox state: not applied in doctor process")
	}
	when ODIN_OS == .Linux {
		if abi, ok := sandbox.landlock_abi_version(); ok {
			fmt.printf("landlock kernel abi: %d\n", abi)
		} else {
			fmt.println("landlock kernel abi: unavailable")
		}
		when ODIN_ARCH == .amd64 {
			fmt.println("seccomp: amd64 deny-list supported")
		} else {
			fmt.println("seccomp: skipped on this architecture, current filter is amd64-only")
		}
	} else when ODIN_OS == .Windows {
		fmt.println("sandbox backend: Windows Job Object spawn helper")
		fmt.println("seccomp: unavailable on Windows")
	} else {
		fmt.println("sandbox backend: unavailable on this OS")
		fmt.println("seccomp: unavailable on this OS")
	}

	print_env("provider", constants.ENV_PROVIDER)
	print_env("model", constants.ENV_MODEL)
	print_env("sandbox", constants.ENV_SANDBOX)
	print_env("mode", constants.ENV_MODE)
	print_env("perms", constants.ENV_PERMS)
	print_env("workspace", constants.ENV_WORKSPACE)
	print_env_present("OPENROUTER_API_KEY", constants.ENV_OPENROUTER_KEY)
	print_env_present("OPENAI_API_KEY", constants.ENV_OPENAI_KEY)
	print_env_present("ANTHROPIC_API_KEY", constants.ENV_ANTHROPIC_KEY)

	tty := stdin_is_tty()
	fmt.printf("stdin tty: %v\n", tty)
	fmt.printf("TERM: %s\n", env_or("TERM", "(unset)"))

	latest := latest_report_path(context.temp_allocator)
	if len(latest) > 0 {
		fmt.printf("latest crash: %s\n", latest)
	} else {
		fmt.println("latest crash: (none)")
	}
	n := store.artifact_gc()
	fmt.printf("artifact gc: removed %d file(s)\n", n)
	fmt.println("tips:")
	fmt.println("  make debug            build with symbols for richer backtraces")
	fmt.println("  NULLRAY_DEBUG=1       verbose stderr lifecycle logs")
	fmt.println("  NULLRAY_SANDBOX=off   isolate sandbox from the fault")
	fmt.println("  nullray --self-test   headless smoke without a TTY")
	fmt.println("  nullray -q QUESTION   simple read-only one-shot answer")
	fmt.println("  man nullray           installed page under share/man/man1")
	fmt.println("  nullray --man         print the bundled man page source")
	return 0
}

@(private)
print_version_line :: proc() {
	fmt.printf("%s %s (built %s %s)\n", constants.APP_NAME, constants.VERSION, constants.BUILD_DATE, constants.BUILD_TIME)
}

@(private)
print_env :: proc(label, key: string) {
	fmt.printf("%s: %s\n", label, env_or(key, "(unset)"))
}

@(private)
print_env_present :: proc(label, key: string) {
	if _, ok := os.lookup_env(key, context.temp_allocator); ok {
		fmt.printf("%s: set\n", label)
	} else {
		fmt.printf("%s: unset\n", label)
	}
}

@(private)
env_or :: proc(key, fallback: string) -> string {
	if v, ok := os.lookup_env(key, context.temp_allocator); ok && len(v) > 0 {
		return v
	}
	return fallback
}

/*
Handle a fatal signal after the platform restored the TTY.
Not async-signal-safe beyond the restore. Best effort dump then exit.
*/
handle_fatal_signal :: proc(sig_num: int, name: string) {
	path := write_report("signal", name, fmt.tprintf("signal %d", sig_num))
	msg := fmt.tprintf("nullray: fatal %s (%d)\n", name, sig_num)
	_, _ = os.write(os.stderr, transmute([]u8)msg)
	if len(path) > 0 {
		line := fmt.tprintf("nullray: crash report: %s\n", path)
		_, _ = os.write(os.stderr, transmute([]u8)line)
		delete(path)
	}
	tip := transmute([]u8)string("nullray: tip: nullray --doctor   and   make debug\n")
	_, _ = os.write(os.stderr, tip)
	os.exit(128 + sig_num)
}
