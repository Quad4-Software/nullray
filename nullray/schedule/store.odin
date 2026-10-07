// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Durable job persistence to .nullray/scheduled_tasks.json. Only durable jobs
are written, session-scoped jobs die with the process. Writes go through a
temp file plus rename so a crash never leaves a truncated store.
*/

package schedule

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

// mtime+size stamp of the last store write or read, so the watcher can
// notice external edits (the watch CLI) without reloading every tick.
g_store_stamp: i64

@(private)
store_file_stamp :: proc(path: string) -> i64 {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return -1
	}
	return i64(time.time_to_unix_nano(fi.modification_time)) ~ i64(fi.size)
}

@(private)
workspace_root :: proc(allocator := context.allocator) -> string {
	if ws := sandbox.workspace_current(); len(ws) > 0 {
		return strings.clone(ws, allocator)
	}
	if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

@(private)
scheduled_path :: proc(allocator := context.allocator) -> string {
	ws := workspace_root(context.temp_allocator)
	p, _ := filepath.join({ws, constants.SCHEDULED_FILE}, allocator)
	return p
}

@(private)
json_escape :: proc(s: string, b: ^strings.Builder) {
	for r in s {
		switch r {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(b, `\u%04x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
}

// Caller must hold g_jobs_mu or call from a single-threaded context.
@(private)
jobs_save_locked :: proc() {
	if !g_persist {
		return
	}
	b := strings.builder_make(runtime.heap_allocator())
	defer strings.builder_destroy(&b)
	strings.write_string(&b, `{"version":1,"jobs":[`)
	first := true
	for j in g_jobs {
		if !j.durable {
			continue
		}
		if !first {
			strings.write_byte(&b, ',')
		}
		first = false
		strings.write_string(&b, `{"id":`)
		fmt.sbprintf(&b, "%d", j.id)
		strings.write_string(&b, `,"spec":"`)
		json_escape(j.spec, &b)
		strings.write_string(&b, `","prompt":"`)
		json_escape(j.prompt, &b)
		strings.write_string(&b, `","session":"`)
		json_escape(j.session_scope, &b)
		strings.write_string(&b, `",`)
		fmt.sbprintf(
			&b,
			`"one_shot":%v,"max_runs":%d,"run_count":%d,"fail_count":%d,"next_fire":%d,"expires":%d`,
			j.one_shot,
			j.max_runs,
			j.run_count,
			j.fail_count,
			j.next_fire,
			j.expires,
		)
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, `]}`)
	path := scheduled_path(context.temp_allocator)
	dir := filepath.dir(path)
	_ = sandbox.mkdir_all(dir)
	tmp := fmt.tprintf("%s.tmp.%d", path, os.get_pid())
	if os.write_entire_file(tmp, transmute([]u8)strings.to_string(b)) == nil {
		if os.rename(tmp, path) != nil {
			_ = os.remove(path)
			if os.rename(tmp, path) != nil {
				_ = os.remove(tmp)
			}
		}
		if stamp := store_file_stamp(path); stamp >= 0 {
			g_store_stamp = stamp
		}
	} else {
		_ = os.remove(tmp)
	}
}

jobs_save :: proc() {
	if !g_persist {
		return
	}
	sync.mutex_lock(&g_jobs_mu)
	jobs_save_locked()
	sync.mutex_unlock(&g_jobs_mu)
}

@(private)
json_int :: proc(v: json.Value) -> i64 {
	#partial switch n in v {
	case json.Integer:
		return i64(n)
	case json.Float:
		return i64(n)
	}
	return 0
}

@(private)
json_bool :: proc(v: json.Value) -> bool {
	if b, ok := v.(json.Boolean); ok {
		return bool(b)
	}
	return false
}

// One durable job from its JSON form. Field strings are heap clones the
// Job owns on success, job_free handles them on failure.
@(private)
job_parse_json :: proc(io: json.Object) -> (j: Job, ok: bool) {
	j = Job{kind = .Prompt}
	if s, s_ok := io["spec"].(json.String); s_ok {
		j.spec = strings.clone(string(s), runtime.heap_allocator())
	}
	if s, s_ok := io["prompt"].(json.String); s_ok {
		j.prompt = strings.clone(string(s), runtime.heap_allocator())
	}
	if s, s_ok := io["session"].(json.String); s_ok {
		j.session_scope = strings.clone(string(s), runtime.heap_allocator())
	}
	j.id = int(json_int(io["id"]))
	j.durable = true
	j.one_shot = json_bool(io["one_shot"])
	j.max_runs = int(json_int(io["max_runs"]))
	j.run_count = int(json_int(io["run_count"]))
	j.fail_count = int(json_int(io["fail_count"]))
	j.next_fire = json_int(io["next_fire"])
	j.expires = json_int(io["expires"])
	if len(j.spec) == 0 || len(j.prompt) == 0 || j.id <= 0 {
		job_free(&j)
		return {}, false
	}
	return j, true
}

// Caller must hold g_jobs_mu. Appends durable jobs found in the store.
@(private)
jobs_load_locked :: proc() {
	path := scheduled_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	arr, a_ok := obj["jobs"].(json.Array)
	if !a_ok {
		return
	}
	max_id := 0
	for item in arr {
		io, io_ok := item.(json.Object)
		if !io_ok {
			continue
		}
		j, j_ok := job_parse_json(io)
		if !j_ok {
			continue
		}
		if j.id > max_id {
			max_id = j.id
		}
		append(&g_jobs, j)
	}
	if max_id >= g_next_id {
		g_next_id = max_id + 1
	}
}

jobs_load :: proc() {
	if !g_persist {
		return
	}
	jobs_load_locked()
	g_store_stamp = store_file_stamp(scheduled_path(context.temp_allocator))
}

/*
Merge an externally modified store (watch add/rm from a CLI process)
into memory. Durable jobs missing from the file were cancelled outside
and are dropped without dirtying the store, new jobs are adopted, and
existing jobs refresh mutable fields while keeping their live
run/fail/queued counters. Caller holds g_jobs_mu.
*/
@(private)
jobs_reload_locked :: proc(path: string) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	arr, a_ok := obj["jobs"].(json.Array)
	if !a_ok {
		return
	}
	file_jobs := make([dynamic]Job, allocator = context.temp_allocator)
	file_ids := make(map[int]bool, allocator = context.temp_allocator)
	for item in arr {
		io, io_ok := item.(json.Object)
		if !io_ok {
			continue
		}
		j, j_ok := job_parse_json(io)
		if !j_ok {
			continue
		}
		file_ids[j.id] = true
		append(&file_jobs, j)
	}
	for i := len(g_jobs) - 1; i >= 0; i -= 1 {
		if g_jobs[i].durable && !file_ids[g_jobs[i].id] {
			job_free(&g_jobs[i])
			ordered_remove(&g_jobs, i)
		}
	}
	for &fj in file_jobs {
		found := false
		for &mj in g_jobs {
			if mj.id != fj.id || !mj.durable {
				continue
			}
			found = true
			if mj.spec != fj.spec {
				delete(mj.spec, runtime.heap_allocator())
				mj.spec = fj.spec
				fj.spec = ""
			}
			if mj.prompt != fj.prompt {
				delete(mj.prompt, runtime.heap_allocator())
				mj.prompt = fj.prompt
				fj.prompt = ""
			}
			if mj.session_scope != fj.session_scope {
				delete(mj.session_scope, runtime.heap_allocator())
				mj.session_scope = fj.session_scope
				fj.session_scope = ""
			}
			mj.one_shot = fj.one_shot
			mj.max_runs = fj.max_runs
			mj.next_fire = fj.next_fire
			mj.expires = fj.expires
			if fj.run_count > mj.run_count {
				mj.run_count = fj.run_count
			}
			if fj.fail_count > mj.fail_count {
				mj.fail_count = fj.fail_count
			}
			break
		}
		if !found {
			if fj.id >= g_next_id {
				g_next_id = fj.id + 1
			}
			append(&g_jobs, fj)
			fj = {}
		}
		job_free(&fj)
	}
}

/*
Called by the watcher each tick. Reloads the durable store only when its
stamp moved since our last save or load, so a running daemon picks up
watch add/rm issued by a second nullray process.
*/
jobs_reload_if_changed :: proc() {
	if !g_persist {
		return
	}
	jobs_ensure_init()
	path := scheduled_path(context.temp_allocator)
	sync.mutex_lock(&g_jobs_mu)
	stamp := store_file_stamp(path)
	if stamp < 0 || stamp == g_store_stamp {
		sync.mutex_unlock(&g_jobs_mu)
		return
	}
	g_store_stamp = stamp
	jobs_reload_locked(path)
	sync.mutex_unlock(&g_jobs_mu)
}
