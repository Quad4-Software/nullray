// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Hybrid loop detection: sliding-window multi-signal detector in the spirit
of agent-loop-guard. Four signals run per step: exact repeat (call-set
signature plus result head), fuzzy repeat (normalized call text near-match
with stagnant output), A-B / A-B-C cycle, and output stagnation (tool
results repeat across differing call sets). A fifth semantic signal
compares an embedding of the call text against window observations via a
pure similarity seam, so tests inject a stub and production can wire the
provider embed API or a hashed trigram fallback.

Signals map to verdict tiers warn, steer, stop. The first fire warns with a
tool-result nudge, a repeat while warned steers harder and raises the
distress flag the escalation path reads, a third fire (or a marked
signature repeating) stops the turn.
*/

package agent

import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

// Cap on the raw result snippet folded into one observation.
LOOP_SNIP_CAP :: 600

Loop_Signal :: enum {
	None,
	Exact,
	Fuzzy,
	Cycle,
	Stagnation,
	Semantic,
}

Loop_Tier :: enum {
	None,
	Warn,
	Steer,
	Stop,
}

Loop_Sem_Mode :: enum {
	Off,
	Hash,
	Embed,
}

// Returns a vector for text, nil on failure. Tests stub this, production
// wires provider embed or the hashed fallback below.
Loop_Embed_Proc :: #type proc(text: string, user: rawptr, allocator := context.allocator) -> []f32

Loop_Obs :: struct {
	sig:         u64,
	result_head: u64,
	calls_norm:  string,
	result_norm: string,
	vec:         []f32,
}

Loop_Detector :: struct {
	obs:         [dynamic]Loop_Obs,
	marks:       Loop_Marks,
	fires:       int,
	window:      int,
	fuzzy:       f64,
	stagnation:  int,
	sem_mode:    Loop_Sem_Mode,
	sem_thresh:  f64,
	embed:       Loop_Embed_Proc,
	embed_user:  rawptr,
	pending_vec: []f32,
	last_period: int,
	alloc:       mem.Allocator,
}

loop_window_from_env :: proc() -> int {
	w := constants.LOOP_WINDOW_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_LOOP_WINDOW, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(strings.trim_space(v)); nok && n > 0 {
			w = n
		}
	}
	if w > constants.LOOP_WINDOW_MAX {
		w = constants.LOOP_WINDOW_MAX
	}
	if w < 4 {
		w = 4
	}
	return w
}

loop_fuzzy_from_env :: proc() -> f64 {
	f := constants.LOOP_FUZZY_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_LOOP_FUZZY, context.temp_allocator); ok {
		s := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		switch s {
		case "0", "off", "false", "no":
			return 0
		}
		if n, nok := strconv.parse_f64(s); nok {
			f = n
		}
	}
	if f > 1 {
		f = 1
	}
	if f < 0 {
		f = 0
	}
	return f
}

loop_stagnation_from_env :: proc() -> int {
	n := constants.LOOP_STAGNATION_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_LOOP_STAGNATION, context.temp_allocator); ok {
		if parsed, pok := strconv.parse_int(strings.trim_space(v)); pok {
			n = parsed
		}
	}
	if n < 0 {
		n = 0
	}
	return n
}

// NULLRAY_LOOP_SEM: off/0 disables, hash forces the pure fallback, on/1
// prefers a real embedder and degrades to hash when none is wired.
loop_sem_mode_from_env :: proc(has_embed: bool) -> Loop_Sem_Mode {
	v, ok := os.lookup_env(constants.ENV_LOOP_SEM, context.temp_allocator)
	if !ok {
		return .Off
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "off", "false", "no":
		return .Off
	case "hash":
		return .Hash
	}
	return has_embed ? .Embed : .Hash
}

loop_sem_threshold_from_env :: proc() -> f64 {
	t := constants.LOOP_SEM_THRESHOLD_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_LOOP_SEM_THRESHOLD, context.temp_allocator); ok {
		if n, nok := strconv.parse_f64(strings.trim_space(v)); nok {
			t = n
		}
	}
	if t > 1 {
		t = 1
	}
	if t < 0 {
		t = 0
	}
	return t
}

loop_detector_init :: proc(allocator := context.allocator) -> Loop_Detector {
	return Loop_Detector{
		obs = make([dynamic]Loop_Obs, 0, constants.LOOP_WINDOW_DEFAULT, allocator),
		window = loop_window_from_env(),
		fuzzy = loop_fuzzy_from_env(),
		stagnation = loop_stagnation_from_env(),
		sem_mode = .Off,
		sem_thresh = loop_sem_threshold_from_env(),
		alloc = allocator,
	}
}

// Attach the semantic path. With sem .Embed the embed proc is the model
// seam, with .Hash the pure trigram fallback runs instead.
loop_detector_set_semantic :: proc(det: ^Loop_Detector, mode: Loop_Sem_Mode, embed: Loop_Embed_Proc, user: rawptr) {
	if det == nil {
		return
	}
	det.sem_mode = mode
	det.embed = embed
	det.embed_user = user
	if mode == .Hash && det.embed == nil {
		det.embed = loop_hash_embed
	}
}

loop_detector_destroy :: proc(det: ^Loop_Detector) {
	if det == nil {
		return
	}
	prev := context.allocator
	context.allocator = det.alloc
	for o in det.obs {
		delete(o.calls_norm)
		delete(o.result_norm)
		delete(o.vec)
	}
	delete(det.obs)
	delete(det.pending_vec)
	context.allocator = prev
	det^ = {}
}

@(private)
loop_entries_view :: proc(det: ^Loop_Detector, allocator := context.temp_allocator) -> []Loop_Entry {
	out := make([]Loop_Entry, len(det.obs), allocator)
	for o, i in det.obs {
		out[i] = Loop_Entry{sig = o.sig, result_head = o.result_head}
	}
	return out
}

@(private)
loop_window_start :: proc(det: ^Loop_Detector) -> int {
	n := len(det.obs)
	start := n - det.window
	if start < 0 {
		start = 0
	}
	return start
}

/*
Run all signals for a pending call set. Order matters: exact first, then
cycle, fuzzy, stagnation, and semantic last since it can cost an embed
call. A clean check resets the fire streak, so the tier ladder only
ratchets on consecutive detections.
*/
loop_detector_check :: proc(det: ^Loop_Detector, calls: []provider.Tool_Call, sig: u64) -> Loop_Signal {
	if det == nil || len(calls) == 0 {
		return .None
	}
	n := len(det.obs)
	det.last_period = 0
	if n > 0 {
		v, period := loop_check(loop_entries_view(det), sig)
		if v == .Identical {
			return .Exact
		}
		if v == .Cycle {
			det.last_period = period
			return .Cycle
		}
	}
	calls_norm := loop_norm_calls(calls)
	if det.fuzzy > 0 && n > 0 {
		last_result := det.obs[n - 1].result_norm
		for i in loop_window_start(det) ..< n {
			o := det.obs[i]
			if o.sig == sig || len(o.result_norm) == 0 || o.result_norm != last_result {
				continue
			}
			if loop_token_jaccard(calls_norm, o.calls_norm) >= det.fuzzy {
				return .Fuzzy
			}
		}
	}
	if det.stagnation >= 2 && n >= det.stagnation {
		norm0 := det.obs[n - 1].result_norm
		if len(norm0) > 0 {
			same := true
			sigs: map[u64]struct{}
			sigs = make(map[u64]struct{}, context.temp_allocator)
			for i in n - det.stagnation ..< n {
				o := det.obs[i]
				if o.result_norm != norm0 {
					same = false
					break
				}
				sigs[o.sig] = {}
			}
			// One signature repeating is the exact signal's job, output
			// stagnation only counts when the calls themselves differ.
			if same && len(sigs) >= 2 {
				return .Stagnation
			}
		}
	}
	if det.sem_mode != .Off && det.embed != nil {
		// A pending vector from an earlier check that never got observed
		// is replaced here, free it under the detector allocator.
		if det.pending_vec != nil {
			prev := context.allocator
			context.allocator = det.alloc
			delete(det.pending_vec)
			context.allocator = prev
			det.pending_vec = nil
		}
		vec := det.embed(calls_norm, det.embed_user, det.alloc)
		if len(vec) > 0 {
			det.pending_vec = vec
			for i in loop_window_start(det) ..< n {
				o := det.obs[i]
				if o.sig == sig || len(o.vec) == 0 {
					continue
				}
				if loop_cosine(vec, o.vec) >= det.sem_thresh {
					return .Semantic
				}
			}
		}
	}
	return .None
}

// Record one executed step: call signature, result head hash, and the raw
// result snippet. Consumes any vector the check staged for this call set.
loop_detector_observe :: proc(det: ^Loop_Detector, sig: u64, result_head: u64, result_snip: string, calls: []provider.Tool_Call) {
	if det == nil {
		return
	}
	calls_norm := loop_norm_calls(calls, det.alloc)
	obs := Loop_Obs{
		sig = sig,
		result_head = result_head,
		calls_norm = calls_norm,
		result_norm = loop_norm_text(result_snip, det.alloc),
		vec = det.pending_vec,
	}
	det.pending_vec = nil
	prev := context.allocator
	context.allocator = det.alloc
	if len(det.obs) >= det.window {
		old := det.obs[0]
		delete(old.calls_norm)
		delete(old.result_norm)
		delete(old.vec)
		ordered_remove(&det.obs, 0)
	}
	append(&det.obs, obs)
	context.allocator = prev
}

// Tier ladder: first fire warns, a second fire steers and raises the
// distress flag the escalation path reads, a third stops the turn. Pure
// so tests drive it directly.
loop_verdict_for_fires :: proc(fires: int) -> (tier: Loop_Tier, stall: bool) {
	if fires >= constants.LOOP_STOP_FIRES {
		return .Stop, false
	}
	if fires >= constants.LOOP_STEER_FIRES {
		return .Steer, true
	}
	return .Warn, false
}

loop_signal_name :: proc(s: Loop_Signal) -> string {
	switch s {
	case .Exact:
		return "exact"
	case .Fuzzy:
		return "fuzzy"
	case .Cycle:
		return "cycle"
	case .Stagnation:
		return "stagnation"
	case .Semantic:
		return "semantic"
	case .None:
	}
	return "none"
}
