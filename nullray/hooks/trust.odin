// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Workspace file trust store.

.nullray/hooks.json runs commands, and .nullray/model_profiles.json steers
sampling and prompt tier, so a cloned hostile repo must not get either for
free. First sight of a workspace-controlled file is denied until the
operator approves it with /hooks trust (or a one-shot NULLRAY_HOOKS_TRUST=1).
Approvals persist per absolute path as {mtime_ns, size} records in
<config dir>/hooks_trusted.json, both fields must match the live stat.
Script tools and harnesses.json reuse this gate through
hooks_workspace_trusted in hooks.odin.
*/

package hooks

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:crash"
import "nullray:sandbox"

// Shared with provider/model_profile.odin, which cannot import this package
// (hooks -> crash -> rag -> provider would cycle) and re-reads this file
// directly for the workspace model_profiles.json gate.
TRUST_STORE_FILE :: "hooks_trusted.json"

Trust_Record :: struct {
	mtime_ns: i64,
	size:     i64,
}

@(private)
g_trust_mu: sync.Mutex
// Approved signatures keyed by absolute path, heap keys, process lifetime.
@(private)
g_trusted: map[string]Trust_Record
// Paths already logged this session so crash.logf does not spam per event.
@(private)
g_warned: map[string]bool
// NULLRAY_HOOKS_TRUST is a one-shot: consumed here instead of unset_env so
// worker threads never mutate the shared environment mid-check.
@(private)
g_env_trust_consumed: bool

/*
JSON string escape onto a builder. fmt %q is NOT JSON: it emits \a, \v and
\xNN escapes that parsers reject. Byte-level pass-through keeps valid UTF-8
intact and escapes the control range, so any payload round-trips through
json.parse without corruption.
*/
write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
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
		case '\b':
			strings.write_string(b, `\b`)
		case '\f':
			strings.write_string(b, `\f`)
		case:
			if c < 0x20 {
				fmt.sbprintf(b, `\u%04x`, c)
			} else {
				strings.write_byte(b, c)
			}
		}
	}
	strings.write_byte(b, '"')
}

@(private)
file_sig :: proc(info: os.File_Info) -> Trust_Record {
	return Trust_Record{
		mtime_ns = time.to_unix_nanoseconds(info.modification_time),
		size     = i64(info.size),
	}
}

// Caller holds g_trust_mu. Replaces in place so a borrowed caller string
// never lands in the map.
@(private)
trust_mark :: proc(path: string, sig: Trust_Record) {
	if g_trusted == nil {
		g_trusted = make(map[string]Trust_Record, runtime.heap_allocator())
	}
	for k in g_trusted {
		if k == path {
			g_trusted[k] = sig
			return
		}
	}
	g_trusted[strings.clone(path, runtime.heap_allocator())] = sig
}

@(private)
trust_store_path :: proc(allocator := context.allocator) -> string {
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	p, _ := filepath.join({cfg, TRUST_STORE_FILE}, allocator)
	return p
}

// Caller holds g_trust_mu.
@(private)
trust_store_load :: proc(allocator := context.allocator) -> map[string]Trust_Record {
	out := make(map[string]Trust_Record, allocator)
	data, rerr := os.read_entire_file(trust_store_path(context.temp_allocator), context.temp_allocator)
	if rerr != nil {
		return out
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return out
	}
	root, ok := doc.(json.Object)
	if !ok {
		return out
	}
	files, fok := root["files"].(json.Object)
	if !fok {
		return out
	}
	for k, v in files {
		ro, rok := v.(json.Object)
		if !rok {
			continue
		}
		rec := Trust_Record{
			mtime_ns = json_num_i64(ro["mtime_ns"]),
			size     = json_num_i64(ro["size"]),
		}
		out[strings.clone(k, allocator)] = rec
	}
	return out
}

/*
mtime_ns exceeds f64's exact-integer range (2^53), and this JSON flavor
parses bare numbers as floats, so the fields are stored as quoted decimal
strings. Bare numbers are still accepted for forward tolerance.
*/
@(private)
json_num_i64 :: proc(v: json.Value) -> i64 {
	#partial switch n in v {
	case json.String:
		parsed, ok := strconv.parse_i64(strings.trim_space(string(n)))
		if ok {
			return parsed
		}
	case json.Integer:
		return i64(n)
	case json.Float:
		return i64(n)
	}
	return 0
}

// Caller holds g_trust_mu. Temp file plus rename so a crash mid-write never
// leaves a truncated trust store (which would deny every workspace).
@(private)
trust_store_save :: proc(entries: map[string]Trust_Record) -> bool {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"version":1,"files":{`)
	first := true
	for k, rec in entries {
		if !first {
			strings.write_byte(&b, ',')
		}
		first = false
		write_json_string(&b, k)
		// Braces stay out of sbprintf format strings, fmt treats { as a
		// directive. mtime_ns/size are quoted because nanosecond epochs
		// exceed f64's exact integer range and this JSON flavor parses bare
		// numbers as floats.
		strings.write_string(&b, `:{"mtime_ns":"`)
		fmt.sbprintf(&b, `%d`, rec.mtime_ns)
		strings.write_string(&b, `","size":"`)
		fmt.sbprintf(&b, `%d`, rec.size)
		strings.write_string(&b, `"}`)
	}
	strings.write_string(&b, `}}`)
	path := trust_store_path(context.temp_allocator)
	if dir := filepath.dir(path); len(dir) > 0 {
		_ = sandbox.mkdir_all(dir)
	}
	tmp := fmt.aprintf("%s.tmp.%d", path, os.get_pid(), allocator = context.temp_allocator)
	if os.write_entire_file(tmp, transmute([]u8)strings.to_string(b)) != nil {
		_ = os.remove(tmp)
		return false
	}
	if os.rename(tmp, path) != nil {
		_ = os.remove(path)
		if os.rename(tmp, path) != nil {
			_ = os.remove(tmp)
			return false
		}
	}
	return true
}

// Record the live stat of path as approved in the persistent store.
@(private)
trust_grant_file :: proc(path: string) -> bool {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return false
	}
	sig := file_sig(info)
	sync.mutex_lock(&g_trust_mu)
	defer sync.mutex_unlock(&g_trust_mu)
	entries := trust_store_load(context.temp_allocator)
	entries[strings.clone(path, context.temp_allocator)] = sig
	if !trust_store_save(entries) {
		return false
	}
	trust_mark(path, sig)
	return true
}

/*
The trust gate. Absent files pass (nothing to run). A matching in-memory or
persisted signature passes. Anything else is denied, the denial is logged
once per session per path and the returned message names the remedy.
*/
@(private)
hooks_file_trusted :: proc(path: string) -> bool {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return true
	}
	sig := file_sig(info)
	sync.mutex_lock(&g_trust_mu)
	defer sync.mutex_unlock(&g_trust_mu)
	if rec, ok := g_trusted[path]; ok && rec == sig {
		return true
	}
	entries := trust_store_load(context.temp_allocator)
	if rec, ok := entries[path]; ok && rec == sig {
		trust_mark(path, sig)
		return true
	}
	// One-shot env trust last so a store-hit does not burn it.
	if !g_env_trust_consumed {
		if v, ok := os.lookup_env(constants.ENV_HOOKS_TRUST, context.temp_allocator); ok {
			switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
			case "1", "true", "yes", "on":
				g_env_trust_consumed = true
				trust_mark(path, sig)
				return true
			}
		}
	}
	if g_warned == nil {
		g_warned = make(map[string]bool, runtime.heap_allocator())
	}
	if _, seen := g_warned[path]; !seen {
		g_warned[strings.clone(path, runtime.heap_allocator())] = true
		crash.logf("workspace file not trusted, denying: %s (approve with /hooks trust)", path)
	}
	return false
}

// Test hook: drop in-memory trust state (the store file is untouched).
hooks_trust_reset_for_test :: proc() {
	sync.mutex_lock(&g_trust_mu)
	defer sync.mutex_unlock(&g_trust_mu)
	for k in g_trusted {
		delete(k, runtime.heap_allocator())
	}
	delete(g_trusted)
	g_trusted = nil
	for k in g_warned {
		delete(k, runtime.heap_allocator())
	}
	delete(g_warned)
	g_warned = nil
	g_env_trust_consumed = false
}
