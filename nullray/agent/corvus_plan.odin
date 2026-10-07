// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
CORVUS planning pass: collects delivered reads and mutations, simulates
dedup and invalidation, emits stub replacements, and builds the per-file
state block. Called from diet_plan on the shared guard arrays.
*/

package agent

import "core:fmt"
import "core:hash"
import "core:slice"
import "core:strings"
import "nullray:provider"

corvus_collect :: proc(
	msgs: []provider.Message,
	call_map: map[string]provider.Tool_Call,
	is_tool: []bool,
	names: []string,
	targets: []string,
	obs: ^[dynamic]Corvus_Obs,
	muts: ^[dynamic]Corvus_Mut,
) {
	for i in 0 ..< len(msgs) {
		if !is_tool[i] {
			continue
		}
		name := names[i]
		m := msgs[i]
		if corvus_tracks(name) {
			path := targets[i]
			if len(path) == 0 || m.is_error || len(m.content) == 0 {
				continue
			}
			// already reduced bodies carry no bytes to dedup
			if is_cleared_tool_content(m.content) ||
				strings.has_prefix(m.content, DIET_STUB_PREFIX) ||
				strings.has_prefix(m.content, CORVUS_STUB_PREFIX) {
				continue
			}
			_, args := diet_call_info(m, call_map)
			o := Corvus_Obs{
				idx = i,
				path = path,
				ref = -1,
				kind = name == "read_file" ? Corvus_Kind.Read : Corvus_Kind.List,
			}
			o.hash = hash.fnv64a(transmute([]byte)m.content)
			if o.kind == .Read {
				off, _ := corvus_arg_int(args, "offset")
				lim, _ := corvus_arg_int(args, "limit")
				o.start = off > 1 ? off : 1
				o.lines = strings.split_lines(
					corvus_body(.Read, m.content),
					context.temp_allocator,
				)
				o.open_end = lim <= 0 || len(o.lines) < lim
			}
			append(obs, o)
		} else if corvus_mutates(name) {
			if !corvus_mut_ok(m) {
				continue
			}
			_, args := diet_call_info(m, call_map)
			whash := u64(0)
			if name == "write_file" {
				if raw := corvus_arg_raw(args, "content"); len(raw) > 0 {
					whash = hash.fnv64a(transmute([]byte)raw)
				}
			}
			paths := make([dynamic]string, context.temp_allocator)
			corvus_arg_paths(args, &paths)
			if len(paths) == 0 && len(targets[i]) > 0 {
				append(&paths, targets[i])
			}
			for p in paths {
				append(muts, Corvus_Mut{idx = i, path = p, whash = whash})
			}
		}
	}
}

// Walk observations in message order and decide stub, keep, or supersede.
corvus_simulate :: proc(obs: []Corvus_Obs, muts: []Corvus_Mut, protected, done: []bool) {
	for oi in 0 ..< len(obs) {
		o := &obs[oi]
		last_mut := -1
		for m in muts {
			if !corvus_mut_affects(m, o) {
				continue
			}
			if m.idx < o.idx && m.idx > last_mut {
				last_mut = m.idx
			}
			if m.idx > o.idx {
				o.stale = true
			}
		}
		// current delivered entries: kept, same kind and path, delivered
		// after the last mutation that precedes this observation
		cur := make([dynamic]int, context.temp_allocator)
		for ej in 0 ..< oi {
			e := &obs[ej]
			if !e.kept || e.kind != o.kind || e.path != o.path {
				continue
			}
			if e.idx <= last_mut {
				continue
			}
			append(&cur, ej)
		}
		hit := -1
		for ej in cur {
			if obs[ej].hash == o.hash {
				hit = ej
				break
			}
		}
		switch {
		case hit >= 0:
			o.stub = .Unchanged
			o.ref = obs[hit].idx
		case o.kind == .Read && corvus_read_covered(o, cur[:], obs):
			o.stub = .Covered
		case:
			o.kept = true
			// a newer different delivery subsumes fully covered entries
			for ej in cur {
				e := &obs[ej]
				if corvus_covers(o, e) {
					e.stub = .Superseded
				}
			}
		}
		if protected[o.idx] || done[o.idx] {
			o.stub = .None
			o.kept = true
		}
	}
}

corvus_stub_text :: proc(name, path, why: string) -> string {
	label := name
	if len(label) == 0 {
		label = "tool"
	}
	if len(path) > 0 {
		return fmt.aprintf(
			"%s %s %s %s]",
			CORVUS_STUB_PREFIX,
			label,
			envelope_sanitize_field(path),
			why,
			allocator = context.temp_allocator,
		)
	}
	return fmt.aprintf("%s %s %s]", CORVUS_STUB_PREFIX, label, why, allocator = context.temp_allocator)
}

corvus_emit :: proc(
	obs: []Corvus_Obs,
	muts: []Corvus_Mut,
	names: []string,
	protected: []bool,
	done: []bool,
	stats: ^Diet_Stats,
	repl: ^[dynamic]Diet_Replacement,
) {
	for oi in 0 ..< len(obs) {
		o := &obs[oi]
		if protected[o.idx] || done[o.idx] {
			continue
		}
		text := ""
		switch {
		case o.stale:
			// point at a fresher copy when one survives the mutations
			last_mut_all := -1
			for m in muts {
				if corvus_mut_affects(m, o) && m.idx > last_mut_all {
					last_mut_all = m.idx
				}
			}
			why := "stale, file modified"
			for e in obs {
				if e.kept && e.kind == o.kind && e.path == o.path && e.idx > last_mut_all {
					why = "stale, see newer read"
					break
				}
			}
			text = corvus_stub_text(names[o.idx], o.path, why)
		case o.stub == .Unchanged:
			text = fmt.aprintf(
				"%s %s %s unchanged since msg %d]",
				CORVUS_STUB_PREFIX,
				names[o.idx],
				envelope_sanitize_field(o.path),
				o.ref,
				allocator = context.temp_allocator,
			)
		case o.stub == .Superseded:
			text = corvus_stub_text(names[o.idx], o.path, "stale, see newer read")
		case o.stub == .Covered:
			text = corvus_stub_text(names[o.idx], o.path, "already delivered, unchanged")
		}
		if len(text) == 0 {
			continue
		}
		append(repl, Diet_Replacement{idx = o.idx, text = text, corvus = true})
		done[o.idx] = true
		stats.corvus.stubbed += 1
	}
}

// Sorted path hash lines for every touched path, capped. A path whose latest
// event is a tracked write shows the write fingerprint when visible, else a
// modified marker so the model knows its last read no longer reflects disk.
corvus_state_block :: proc(obs: []Corvus_Obs, muts: []Corvus_Mut, stats: ^Diet_Stats) -> string {
	states := make(map[string]Corvus_State, context.temp_allocator)
	for o in obs {
		if o.stale {
			continue
		}
		if !o.kept && o.stub != .Unchanged && o.stub != .Covered {
			continue
		}
		if s, ok := states[o.path]; !ok || o.idx > s.idx {
			states[o.path] = Corvus_State{hash = o.hash, idx = o.idx}
		}
	}
	for m in muts {
		if s, ok := states[m.path]; !ok || m.idx > s.idx {
			states[m.path] = Corvus_State{hash = m.whash, idx = m.idx, modified = m.whash == 0}
		}
	}
	if len(states) == 0 {
		return ""
	}
	keys := make([dynamic]string, 0, len(states), context.temp_allocator)
	for k in states {
		append(&keys, k)
	}
	slice.sort_by(keys[:], proc(a, b: string) -> bool { return strings.compare(a, b) < 0 })
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "\n")
	strings.write_string(&b, CORVUS_STATE_MARK)
	count := 0
	for k in keys {
		if count >= CORVUS_STATE_CAP {
			break
		}
		s := states[k]
		if s.modified {
			fmt.sbprintf(&b, "\n%s modified", envelope_sanitize_field(k))
		} else {
			fmt.sbprintf(&b, "\n%s %x", envelope_sanitize_field(k), s.hash)
		}
		count += 1
	}
	out := strings.to_string(b)
	stats.corvus.state_entries = count
	stats.corvus.state_chars = len(out)
	return out
}

// CORVUS planning pass. Runs inside diet_plan on the same guards so stub,
// supersede, and truncation passes never see a message twice. Returns the
// optional state block for the caller to append at the last position.
corvus_scan :: proc(
	msgs: []provider.Message,
	call_map: map[string]provider.Tool_Call,
	is_tool: []bool,
	names: []string,
	targets: []string,
	protected: []bool,
	done: []bool,
	stats: ^Diet_Stats,
	repl: ^[dynamic]Diet_Replacement,
) -> string {
	obs := make([dynamic]Corvus_Obs, context.temp_allocator)
	muts := make([dynamic]Corvus_Mut, context.temp_allocator)
	corvus_collect(msgs, call_map, is_tool, names, targets, &obs, &muts)
	if len(obs) == 0 && len(muts) == 0 {
		return ""
	}
	corvus_simulate(obs[:], muts[:], protected, done)
	corvus_emit(obs[:], muts[:], names, protected, done, stats, repl)
	return corvus_state_block(obs[:], muts[:], stats)
}
