// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Background run_shell tasks. background=true returns a pollable id and
writes output to .nullray/tasks/<id>.log. Pass task_id to poll.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Bg_Task :: struct {
	id:        string,
	command:   string,
	log_path:  string,
	process:   os.Process,
	log_file:  ^os.File,
	done:      bool,
	exit_code: int,
	err:       string,
}

@(private)
g_bg_mu: sync.Mutex
@(private)
g_bg_tasks: [dynamic]Bg_Task

bg_tasks_dir :: proc(allocator := context.temp_allocator) -> string {
	ws := workspace_root(allocator)
	p, _ := filepath.join({ws, constants.TASKS_DIR}, allocator)
	return p
}

@(private)
bg_new_id :: proc(allocator := context.allocator) -> string {
	n := time.to_unix_nanoseconds(time.now())
	return fmt.aprintf("%x", u64(n), allocator = allocator)
}

shell_bg_start :: proc(command, workspace: string, env: []string, allocator := context.allocator) -> (result: string, err: string) {
	dir := bg_tasks_dir()
	_ = sandbox.mkdir_all(dir)
	id := bg_new_id(allocator)
	log_path, _ := filepath.join({dir, fmt.tprintf("%s.log", id)}, allocator)
	f, ferr := os.open(log_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if ferr != nil {
		delete(id)
		delete(log_path)
		return "", fmt.aprintf("open task log failed: %v", ferr, allocator = allocator)
	}
	argv: [3]string
	when ODIN_OS == .Windows {
		argv = {"cmd.exe", "/C", command}
	} else {
		argv = {"/bin/sh", "-c", command}
	}
	desc := os.Process_Desc{
		working_dir = workspace,
		command = argv[:],
		env = env,
		stdout = f,
		stderr = f,
	}
	process, start_err := os.process_start(desc)
	if start_err != nil {
		os.close(f)
		delete(id)
		delete(log_path)
		return "", fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
	}
	shell_claim_process_group(process)
	shell_register_active(process)
	task := Bg_Task{
		id = id,
		command = strings.clone(command, allocator),
		log_path = log_path,
		process = process,
		log_file = f,
	}
	sync.mutex_lock(&g_bg_mu)
	if g_bg_tasks == nil {
		g_bg_tasks = make([dynamic]Bg_Task)
	}
	append(&g_bg_tasks, task)
	idx := new(int)
	idx^ = len(g_bg_tasks) - 1
	sync.mutex_unlock(&g_bg_mu)
	thread.create_and_start_with_data(idx, bg_wait_worker)
	return fmt.aprintf(
		"task_id=%s status=running log=%s\ncommand: %s",
		id,
		log_path,
		command,
		allocator = allocator,
	), ""
}

@(private)
bg_wait_worker :: proc(data: rawptr) {
	idxp := cast(^int)data
	idx := idxp^
	free(idxp)
	sync.mutex_lock(&g_bg_mu)
	if idx < 0 || idx >= len(g_bg_tasks) {
		sync.mutex_unlock(&g_bg_mu)
		return
	}
	proc_copy := g_bg_tasks[idx].process
	logf := g_bg_tasks[idx].log_file
	sync.mutex_unlock(&g_bg_mu)
	state, werr := os.process_wait(proc_copy)
	shell_clear_active(proc_copy)
	os.close(logf)
	sync.mutex_lock(&g_bg_mu)
	defer sync.mutex_unlock(&g_bg_mu)
	if idx < 0 || idx >= len(g_bg_tasks) {
		return
	}
	g_bg_tasks[idx].done = true
	g_bg_tasks[idx].exit_code = state.exit_code
	if werr != nil {
		g_bg_tasks[idx].err = fmt.aprintf("%v", werr)
	}
}

shell_bg_poll :: proc(task_id: string, allocator := context.allocator) -> (result: string, err: string) {
	id := strings.trim_space(task_id)
	if len(id) == 0 {
		return "", strings.clone("task_id required", allocator)
	}
	sync.mutex_lock(&g_bg_mu)
	defer sync.mutex_unlock(&g_bg_mu)
	for t in g_bg_tasks {
		if t.id != id {
			continue
		}
		tail := bg_log_tail(t.log_path, allocator)
		status := "running"
		if t.done {
			status = fmt.tprintf("exited %d", t.exit_code)
		}
		return fmt.aprintf("task_id=%s status=%s log=%s\n%s", t.id, status, t.log_path, tail, allocator = allocator), ""
	}
	dir := bg_tasks_dir()
	log_path, _ := filepath.join({dir, fmt.tprintf("%s.log", id)}, context.temp_allocator)
	if os.exists(log_path) {
		tail := bg_log_tail(log_path, allocator)
		return fmt.aprintf("task_id=%s status=unknown log=%s\n%s", id, log_path, tail, allocator = allocator), ""
	}
	return "", fmt.aprintf("unknown task_id: %s", id, allocator = allocator)
}

@(private)
bg_log_tail :: proc(path: string, allocator := context.allocator) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return strings.clone("(no output yet)", allocator)
	}
	s := string(data)
	max := 4000
	if len(s) > max {
		s = s[len(s) - max:]
	}
	return strings.clone(s, allocator)
}
