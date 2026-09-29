// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Subprocess runner for Git and Fossil commands.
*/

package vcs

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"

/*
A git config file that exists on disk but cannot be opened is fatal to every
git invocation, and the sandbox keeps $HOME out. When the user-level config is
unreachable, fall back to the repo's own config so commands still run; a
missing file is fine because git treats it as absent.
*/
@(private)
git_env :: proc(repo: Repo) -> []string {
	home, _ := os.lookup_env("HOME", context.temp_allocator)
	xdg, xok := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator)
	candidates: [dynamic]string
	if len(home) > 0 {
		append(&candidates, strings.concatenate({home, "/.gitconfig"}, context.temp_allocator))
		if xok && len(xdg) > 0 {
			append(&candidates, strings.concatenate({xdg, "/git/config"}, context.temp_allocator))
		} else {
			append(&candidates, strings.concatenate({home, "/.config/git/config"}, context.temp_allocator))
		}
	}
	blocked := false
	for p in candidates {
		h, oerr := os.open(p)
		if oerr == nil {
			os.close(h)
			continue
		}
		missing := false
		#partial switch e in oerr {
		case os.General_Error:
			missing = e == .Not_Exist
		}
		if !missing {
			blocked = true
			break
		}
	}
	if !blocked {
		return nil
	}
	base, berr := os.environ(context.temp_allocator)
	out := make([dynamic]string, context.temp_allocator)
	if berr == nil {
		for e in base {
			if strings.has_prefix(e, "GIT_CONFIG_GLOBAL=") ||
			   strings.has_prefix(e, "GIT_CONFIG_NOSYSTEM=") {
				continue
			}
			append(&out, strings.clone(e, context.temp_allocator))
		}
	}
	append(
		&out,
		strings.concatenate(
			{"GIT_CONFIG_GLOBAL=", repo.root, "/.git/config"},
			context.temp_allocator,
		),
	)
	append(&out, "GIT_CONFIG_NOSYSTEM=1")
	return out[:]
}

@(private)
run :: proc(repo: Repo, argv: []string, allocator := context.allocator) -> (out: string, err: string) {
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = repo.root,
			command = argv,
			env = git_env(repo),
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("VCS exec failed: %v", start_err, allocator = allocator)
		}
	}

	stdout_b := make([dynamic]byte, context.temp_allocator)
	stderr_b := make([dynamic]byte, context.temp_allocator)
	buf: [2048]u8
	start := time.now()
	timed_out := false
	exited := false
	exit_code := 0
	for !exited {
		has_stdout, _ := os.pipe_has_data(stdout_r)
		if has_stdout {
			n, _ := os.read(stdout_r, buf[:])
			if n > 0 {
				append(&stdout_b, ..buf[:n])
			}
		}
		has_stderr, _ := os.pipe_has_data(stderr_r)
		if has_stderr {
			n, _ := os.read(stderr_r, buf[:])
			if n > 0 {
				append(&stderr_b, ..buf[:n])
			}
		}
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			exited = true
			exit_code = state.exit_code
			break
		}
		if time.since(start) >= time.Second * 30 {
			timed_out = true
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			exited = true
			exit_code = state.exit_code
		}
	}
	for {
		n, rerr := os.read(stdout_r, buf[:])
		if n > 0 {
			append(&stdout_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	for {
		n, rerr := os.read(stderr_r, buf[:])
		if n > 0 {
			append(&stderr_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	combined := fmt.aprintf("%s%s", string(stdout_b[:]), string(stderr_b[:]), allocator = allocator)
	if timed_out {
		return combined, strings.clone("VCS command timed out", allocator)
	}
	if exit_code != 0 {
		return combined, fmt.aprintf("VCS command failed with exit %d: %s", exit_code, combined, allocator = allocator)
	}
	return combined, ""
}
