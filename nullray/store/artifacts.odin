// SPDX-License-Identifier: 0BSD
/*
Session-local artifact store for large tool payloads (LID harness).
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

@(private)
g_artifact_mu: sync.Mutex

@(private)
g_artifact_seq: int

artifact_dir :: proc(allocator := context.allocator) -> string {
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		if st := sandbox.state(); st != nil {
			ws = st.workspace
		}
	}
	if len(ws) == 0 {
		ws = "."
	}
	joined, err := filepath.join({ws, constants.ARTIFACTS_DIR}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", ws, constants.ARTIFACTS_DIR, allocator = allocator)
	}
	return joined
}

ensure_artifact_dir :: proc() -> bool {
	dir := artifact_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	return true
}

artifact_id_ok :: proc(id: string) -> bool {
	if len(id) == 0 || len(id) > 64 {
		return false
	}
	for c in id {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
		case:
			return false
		}
	}
	return true
}

artifact_path :: proc(id: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if !artifact_id_ok(id) {
		return "", false
	}
	dir := artifact_dir(context.temp_allocator)
	joined, err := filepath.join({dir, fmt.tprintf("%s.txt", id)}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s.txt", dir, id, allocator = allocator), true
	}
	return joined, true
}

/*
Store body under .nullray/artifacts/<id>.txt. Caller owns returned id.
*/
artifact_store :: proc(body: string, allocator := context.allocator) -> (id: string, ok: bool) {
	ensure_artifact_dir()
	sync.mutex_lock(&g_artifact_mu)
	g_artifact_seq += 1
	seq := g_artifact_seq
	sync.mutex_unlock(&g_artifact_mu)
	ts := time.time_to_unix_nano(time.now())
	id = fmt.aprintf("a%d_%d", ts, seq, allocator = allocator)
	path, pok := artifact_path(id, context.temp_allocator)
	if !pok {
		delete(id)
		return "", false
	}
	if os.write_entire_file(path, transmute([]u8)body) != nil {
		delete(id)
		return "", false
	}
	return id, true
}

artifact_read :: proc(id: string, allocator := context.allocator) -> (text: string, err: string) {
	path, ok := artifact_path(id, context.temp_allocator)
	if !ok {
		return "", strings.clone("invalid artifact id", allocator)
	}
	data, rerr := os.read_entire_file(path, allocator)
	if rerr != nil {
		return "", fmt.aprintf("artifact not found: %s", id, allocator = allocator)
	}
	return string(data), ""
}

artifact_grep :: proc(id, pattern: string, allocator := context.allocator) -> (text: string, err: string) {
	body, rerr := artifact_read(id, context.temp_allocator)
	if len(rerr) > 0 {
		return "", strings.clone(rerr, allocator)
	}
	if len(pattern) == 0 {
		return "", strings.clone("pattern required", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	lines := strings.split_lines(body, context.temp_allocator)
	n := 0
	for line, i in lines {
		if strings.contains(line, pattern) {
			fmt.sbprintf(&b, "%d:%s\n", i + 1, line)
			n += 1
			if n >= constants.MAX_GREP_MATCHES {
				strings.write_string(&b, "... truncated\n")
				break
			}
		}
	}
	if n == 0 {
		strings.write_string(&b, "no matches\n")
	}
	return strings.to_string(b), ""
}

artifact_chars_threshold :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_ARTIFACT_CHARS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 0 {
			return n
		}
	}
	return constants.ARTIFACT_CHARS_DEFAULT
}

Artifact_File_Info :: struct {
	path:  string,
	size:  i64,
	mtime: i64,
}

/*
Delete aged or excess artifacts under .nullray/artifacts. Oldest first when over quota.
Returns number of files removed.
*/
artifact_gc :: proc(
	max_bytes: i64 = constants.ARTIFACT_GC_MAX_BYTES,
	max_age_days: int = constants.ARTIFACT_GC_MAX_AGE_DAYS,
) -> int {
	dir := artifact_dir(context.temp_allocator)
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return 0
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	now := time.time_to_unix(time.now())
	max_age_secs: i64 = 0
	if max_age_days > 0 {
		max_age_secs = i64(max_age_days) * 24 * 60 * 60
	}
	infos := make([dynamic]Artifact_File_Info, context.temp_allocator)
	total: i64 = 0
	removed := 0
	for e in entries {
		if e.type == .Directory {
			continue
		}
		name := e.name
		if !strings.has_suffix(name, ".txt") {
			continue
		}
		id := name[:len(name) - 4]
		if !artifact_id_ok(id) {
			continue
		}
		path, pok := artifact_path(id, context.temp_allocator)
		if !pok {
			continue
		}
		size := e.size
		mtime := time.to_unix_seconds(e.modification_time)
		if max_age_secs > 0 && (now - mtime) > max_age_secs {
			if os.remove(path) == nil {
				removed += 1
			}
			continue
		}
		total += size
		append(&infos, Artifact_File_Info{
			path = strings.clone(path, context.temp_allocator),
			size = size,
			mtime = mtime,
		})
	}
	if max_bytes <= 0 || total <= max_bytes {
		return removed
	}
	for i in 0 ..< len(infos) {
		for j in i + 1 ..< len(infos) {
			if infos[j].mtime < infos[i].mtime {
				infos[i], infos[j] = infos[j], infos[i]
			}
		}
	}
	for info in infos {
		if total <= max_bytes {
			break
		}
		if os.remove(info.path) == nil {
			total -= info.size
			removed += 1
		}
	}
	return removed
}
