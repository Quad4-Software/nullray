// SPDX-License-Identifier: 0BSD
#+build !windows
/*
Unix privilege broker: child started before Landlock, runs elevated cmds.
*/

package elevate

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"

Broker :: struct {
	sock_path: string,
	process:   os.Process,
	started:   bool,
}

g_broker: Broker
g_broker_mu: sync.Mutex

broker_available :: proc() -> bool {
	sync.mutex_lock(&g_broker_mu)
	defer sync.mutex_unlock(&g_broker_mu)
	return g_broker.started
}

broker_sock_path :: proc() -> string {
	sync.mutex_lock(&g_broker_mu)
	defer sync.mutex_unlock(&g_broker_mu)
	return g_broker.sock_path
}

broker_start :: proc(exe_path: string) -> bool {
	sync.mutex_lock(&g_broker_mu)
	defer sync.mutex_unlock(&g_broker_mu)
	if g_broker.started {
		return true
	}
	if len(exe_path) == 0 {
		return false
	}
	dir := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = os.get_env("TMPDIR", context.temp_allocator)
	}
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, jerr := filepath.join(
		{dir, fmt.tprintf("nullray-elevate-%d.sock", os.get_pid())},
		context.allocator,
	)
	if jerr != nil {
		return false
	}
	_ = os.remove(path)

	argv := []string{exe_path, "--elevate-broker", path}
	desc := os.Process_Desc{
		command = argv,
	}
	bp, err := os.process_start(desc)
	if err != nil {
		delete(path)
		return false
	}
	g_broker.process = bp
	g_broker.sock_path = path
	g_broker.started = true
	os.set_env(constants.ENV_ELEVATE_BROKER_SOCK, path)
	for i := 0; i < 50; i += 1 {
		if os.exists(path) {
			break
		}
		thread.yield()
	}
	return true
}

broker_stop :: proc() {
	sync.mutex_lock(&g_broker_mu)
	defer sync.mutex_unlock(&g_broker_mu)
	if !g_broker.started {
		return
	}
	_ = os.process_kill(g_broker.process)
	_, _ = os.process_wait(g_broker.process, time.Second * 5)
	if len(g_broker.sock_path) > 0 {
		_ = os.remove(g_broker.sock_path)
		_ = os.remove(fmt.tprintf("%s.d", g_broker.sock_path))
		delete(g_broker.sock_path)
	}
	g_broker = {}
}

broker_run :: proc(
	cmd: string,
	cwd: string,
	sudo_askpass: string,
	doas_askpass: string,
	allocator := context.allocator,
) -> Result {
	req_dir := fmt.tprintf("%s.d", g_broker.sock_path)
	_ = os.make_directory(req_dir)

	id := fmt.tprintf("%d-%d", os.get_pid(), time.now()._nsec)
	req_path := fmt.tprintf("%s/req-%s.json", req_dir, id)
	resp_path := fmt.tprintf("%s/resp-%s.json", req_dir, id)
	_ = os.remove(resp_path)

	payload := fmt.aprintf(
		`{"cmd":%q,"cwd":%q,"sudo_askpass":%q,"doas_askpass":%q}`,
		cmd,
		cwd,
		sudo_askpass,
		doas_askpass,
		allocator = context.temp_allocator,
	)
	if os.write_entire_file(req_path, transmute([]byte)payload) != nil {
		return exec_capture(cmd, cwd, sudo_askpass, doas_askpass, allocator)
	}

	for i := 0; i < 600; i += 1 {
		data, rerr := os.read_entire_file(resp_path, context.temp_allocator)
		if rerr == nil {
			_ = os.remove(req_path)
			_ = os.remove(resp_path)
			return parse_broker_response(string(data), allocator)
		}
		thread.yield()
	}
	_ = os.remove(req_path)
	return exec_capture(cmd, cwd, sudo_askpass, doas_askpass, allocator)
}

@(private)
parse_broker_response :: proc(data: string, allocator := context.allocator) -> Result {
	res: Result
	doc, err := json.parse(transmute([]byte)data, json.DEFAULT_SPECIFICATION, false, context.temp_allocator)
	if err != nil {
		res.kind = .Exec_Failed
		res.outcome = .Failed
		res.err = strings.clone("broker response parse failed", allocator)
		res.exit_code = 1
		return res
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		res.kind = .Exec_Failed
		res.outcome = .Failed
		res.err = strings.clone("broker response not object", allocator)
		res.exit_code = 1
		return res
	}
	if v, ok := obj["exit"]; ok {
		if n, is_n := v.(json.Integer); is_n {
			res.exit_code = int(n)
		}
	}
	if v, ok := obj["stdout"]; ok {
		if s, is_s := v.(json.String); is_s {
			res.stdout = strings.clone(s, allocator)
		}
	}
	if v, ok := obj["stderr"]; ok {
		if s, is_s := v.(json.String); is_s {
			res.stderr = strings.clone(s, allocator)
		}
	}
	if v, ok := obj["err"]; ok {
		if s, is_s := v.(json.String); is_s {
			res.err = strings.clone(s, allocator)
		}
	}
	return res
}

run_elevate_broker_server :: proc(sock_path: string) -> int {
	req_dir := fmt.tprintf("%s.d", sock_path)
	_ = os.make_directory(req_dir)
	ready := "ready"
	_ = os.write_entire_file(sock_path, transmute([]byte)ready)

	for {
		fis, err := os.read_directory_by_path(req_dir, -1, context.temp_allocator)
		if err != nil {
			time.sleep(20 * time.Millisecond)
			continue
		}
		handled := false
		for fi in fis {
			name := fi.name
			if !strings.has_prefix(name, "req-") || !strings.has_suffix(name, ".json") {
				continue
			}
			req_path := fmt.tprintf("%s/%s", req_dir, name)
			data, rerr := os.read_entire_file(req_path, context.temp_allocator)
			if rerr != nil {
				continue
			}
			_ = os.remove(req_path)
			handled = true
			cmd, cwd, sudo_a, doas_a := parse_broker_request(string(data))
			res := exec_capture(cmd, cwd, sudo_a, doas_a, context.temp_allocator)
			resp := fmt.aprintf(
				`{"exit":%d,"stdout":%q,"stderr":%q,"err":%q}`,
				res.exit_code,
				res.stdout,
				res.stderr,
				res.err,
				allocator = context.temp_allocator,
			)
			id := name[4:len(name) - 5]
			resp_path := fmt.tprintf("%s/resp-%s.json", req_dir, id)
			_ = os.write_entire_file(resp_path, transmute([]byte)resp)
			result_destroy(&res)
		}
		if !handled {
			time.sleep(20 * time.Millisecond)
		} else {
			thread.yield()
		}
	}
}

@(private)
parse_broker_request :: proc(data: string) -> (cmd, cwd, sudo_a, doas_a: string) {
	doc, err := json.parse(transmute([]byte)data, json.DEFAULT_SPECIFICATION, false, context.temp_allocator)
	if err != nil {
		return "", "", "", ""
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return "", "", "", ""
	}
	if v, ok := obj["cmd"]; ok {
		if s, is_s := v.(json.String); is_s {
			cmd = s
		}
	}
	if v, ok := obj["cwd"]; ok {
		if s, is_s := v.(json.String); is_s {
			cwd = s
		}
	}
	if v, ok := obj["sudo_askpass"]; ok {
		if s, is_s := v.(json.String); is_s {
			sudo_a = s
		}
	}
	if v, ok := obj["doas_askpass"]; ok {
		if s, is_s := v.(json.String); is_s {
			doas_a = s
		}
	}
	return
}
