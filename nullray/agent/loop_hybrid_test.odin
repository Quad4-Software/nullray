// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Hybrid loop detector tests: all four signals, the semantic seam, the
hashed fallback, and the tier ladder.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

@(private)
mk_det :: proc(fuzzy: f64, stag: int) -> Loop_Detector {
	det := loop_detector_init()
	det.fuzzy = fuzzy
	det.stagnation = stag
	return det
}

@(private)
det_exec :: proc(det: ^Loop_Detector, calls: []provider.Tool_Call, result: string) {
	sig := loop_sig_of_calls(calls)
	head := u64(0xcbf29ce484222325)
	left := LOOP_RESULT_HEAD_BYTES
	head = loop_result_head_update(head, result, &left)
	loop_detector_observe(det, sig, head, result, calls)
}

@(test)
test_hybrid_exact_repeat_fires :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	calls := mk_calls({"run_shell", `{"cmd":"ls"}`})
	det_exec(&det, calls, "a\nb\n")
	det_exec(&det, calls, "a\nb\n")
	sig := loop_sig_of_calls(calls)
	testing.expect(t, loop_detector_check(&det, calls, sig) == .Exact)
}

@(test)
test_hybrid_poller_stays_clean :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	calls := mk_calls({"run_shell", `{"cmd":"date"}`})
	sig := loop_sig_of_calls(calls)
	det_exec(&det, calls, "t1")
	det_exec(&det, calls, "t2")
	det_exec(&det, calls, "t3")
	testing.expect(t, loop_detector_check(&det, calls, sig) == .None)
}

@(test)
test_hybrid_fuzzy_repeat_fires :: proc(t: ^testing.T) {
	det := mk_det(0.75, 3)
	defer loop_detector_destroy(&det)
	a := mk_calls({"run_shell", `{"cmd":"ls -l src"}`})
	b := mk_calls({"read_file", `{"path":"other"}`})
	det_exec(&det, a, "SAME_OUT")
	det_exec(&det, b, "SAME_OUT")
	// Near-identical call bytes, different signature, and the output
	// already stagnated on the same text.
	incoming := mk_calls({"run_shell", `{"cmd":"ls -l src/"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .Fuzzy)
}

@(test)
test_hybrid_fuzzy_ignores_fresh_output :: proc(t: ^testing.T) {
	det := mk_det(0.75, 3)
	defer loop_detector_destroy(&det)
	a := mk_calls({"run_shell", `{"cmd":"ls -l src"}`})
	b := mk_calls({"read_file", `{"path":"other"}`})
	det_exec(&det, a, "OUT_A")
	det_exec(&det, b, "OUT_B")
	incoming := mk_calls({"run_shell", `{"cmd":"ls -l src/"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .None)
}

@(test)
test_hybrid_cycle_fires :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	a := mk_calls({"read_file", `{"path":"a"}`})
	b := mk_calls({"read_file", `{"path":"b"}`})
	results := []string{"r1", "r2", "r3", "r4", "r5"}
	sigs := [5][]provider.Tool_Call{a, b, a, b, a}
	for c, i in sigs {
		det_exec(&det, c, results[i])
	}
	testing.expect(t, loop_detector_check(&det, b, loop_sig_of_calls(b)) == .Cycle)
	testing.expect_value(t, det.last_period, 2)
}

@(test)
test_hybrid_stagnation_fires_across_differing_calls :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	det_exec(&det, mk_calls({"read_file", `{"path":"a"}`}), "STUCK")
	det_exec(&det, mk_calls({"run_shell", `{"cmd":"ls"}`}), "STUCK")
	det_exec(&det, mk_calls({"grep", `{"q":"zzz"}`}), "STUCK")
	incoming := mk_calls({"read_file", `{"path":"b"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .Stagnation)
}

@(test)
test_hybrid_stagnation_needs_distinct_sigs :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	same := mk_calls({"run_shell", `{"cmd":"ls"}`})
	det_exec(&det, same, "STUCK")
	det_exec(&det, same, "STUCK")
	det_exec(&det, same, "STUCK")
	// Same signature with same output is the exact signal's turf.
	incoming := mk_calls({"run_shell", `{"cmd":"ls"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .Exact)
}

@(private)
test_embed_stub :: proc(text: string, user: rawptr, allocator := context.allocator) -> []f32 {
	_ = user
	v := make([]f32, 2, allocator)
	if strings.contains(text, "alpha") {
		v[0] = 1
	} else {
		v[1] = 1
	}
	return v
}

@(test)
test_hybrid_semantic_via_stub :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	loop_detector_set_semantic(&det, .Embed, test_embed_stub, nil)
	// Seed one observation whose vector is staged by check then consumed
	// by observe, exactly like the turn loop drives it.
	seed := mk_calls({"run_shell", `{"cmd":"alpha scan"}`})
	seed_sig := loop_sig_of_calls(seed)
	_ = loop_detector_check(&det, seed, seed_sig)
	det_exec(&det, seed, "OUT_A")
	other := mk_calls({"read_file", `{"path":"beta"}`})
	_ = loop_detector_check(&det, other, loop_sig_of_calls(other))
	det_exec(&det, other, "OUT_B")
	// New text, different signature, still alpha-shaped.
	incoming := mk_calls({"run_shell", `{"cmd":"alpha rescan now"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .Semantic)
}

@(test)
test_hybrid_semantic_hash_fallback :: proc(t: ^testing.T) {
	det := mk_det(0.8, 3)
	defer loop_detector_destroy(&det)
	loop_detector_set_semantic(&det, .Hash, nil, nil)
	testing.expect(t, det.embed != nil)
	seed := mk_calls({"run_shell", `{"cmd":"inspect the alpha widget"}`})
	_ = loop_detector_check(&det, seed, loop_sig_of_calls(seed))
	det_exec(&det, seed, "OUT_A")
	other := mk_calls({"read_file", `{"path":"beta"}`})
	_ = loop_detector_check(&det, other, loop_sig_of_calls(other))
	det_exec(&det, other, "OUT_B")
	incoming := mk_calls({"run_shell", `{"cmd":"inspect  the  alpha widget"}`})
	testing.expect(t, loop_detector_check(&det, incoming, loop_sig_of_calls(incoming)) == .Semantic)
}

@(test)
test_hybrid_semantic_cosine :: proc(t: ^testing.T) {
	a := []f32{1, 0, 0}
	testing.expect(t, loop_cosine(a, a) > 0.99)
	b := []f32{0, 1, 0}
	testing.expect(t, loop_cosine(a, b) < 0.01)
	testing.expect(t, loop_cosine(a, nil) == 0)
}

@(test)
test_hybrid_verdict_ladder :: proc(t: ^testing.T) {
	tier, stall := loop_verdict_for_fires(1)
	testing.expect(t, tier == .Warn)
	testing.expect(t, !stall)
	tier, stall = loop_verdict_for_fires(2)
	testing.expect(t, tier == .Steer)
	testing.expect(t, stall)
	tier, stall = loop_verdict_for_fires(3)
	testing.expect(t, tier == .Stop)
	testing.expect(t, !stall)
}

@(test)
test_hybrid_norm_and_jaccard :: proc(t: ^testing.T) {
	n := loop_norm_text(`{"Cmd":  "LS   -l"}`)
	testing.expect_value(t, n, "cmd ls l")
	testing.expect(t, loop_token_jaccard("a b c", "a b c") == 1)
	testing.expect(t, loop_token_jaccard("a b c", "a b d") > 0.4)
	testing.expect(t, loop_token_jaccard("a b c", "x y z") == 0)
	testing.expect(t, loop_token_jaccard("", "x") == 0)
}

@(test)
test_hybrid_window_env_knobs :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_LOOP_WINDOW)
	os.unset_env(constants.ENV_LOOP_FUZZY)
	os.unset_env(constants.ENV_LOOP_STAGNATION)
	os.unset_env(constants.ENV_LOOP_SEM)
	testing.expect_value(t, loop_window_from_env(), constants.LOOP_WINDOW_DEFAULT)
	os.set_env(constants.ENV_LOOP_WINDOW, "99")
	defer os.unset_env(constants.ENV_LOOP_WINDOW)
	testing.expect_value(t, loop_window_from_env(), constants.LOOP_WINDOW_MAX)
	os.set_env(constants.ENV_LOOP_FUZZY, "off")
	defer os.unset_env(constants.ENV_LOOP_FUZZY)
	testing.expect(t, loop_fuzzy_from_env() == 0)
	os.set_env(constants.ENV_LOOP_STAGNATION, "5")
	defer os.unset_env(constants.ENV_LOOP_STAGNATION)
	testing.expect_value(t, loop_stagnation_from_env(), 5)
	testing.expect(t, loop_sem_mode_from_env(false) == .Off)
	os.set_env(constants.ENV_LOOP_SEM, "1")
	defer os.unset_env(constants.ENV_LOOP_SEM)
	testing.expect(t, loop_sem_mode_from_env(true) == .Embed)
	testing.expect(t, loop_sem_mode_from_env(false) == .Hash)
	os.set_env(constants.ENV_LOOP_SEM, "hash")
	testing.expect(t, loop_sem_mode_from_env(true) == .Hash)
}

@(test)
test_hybrid_observe_evicts_oldest :: proc(t: ^testing.T) {
	det := loop_detector_init()
	defer loop_detector_destroy(&det)
	det.window = 4
	calls := mk_calls({"run_shell", `{"cmd":"ls"}`})
	for i in 0 ..< 6 {
		head := u64(0xcbf29ce484222325)
		left := LOOP_RESULT_HEAD_BYTES
		head = loop_result_head_update(head, "r", &left)
		loop_detector_observe(&det, u64(100 + i), head, "r", calls)
	}
	testing.expect_value(t, len(det.obs), 4)
	testing.expect_value(t, det.obs[3].sig, u64(105))
	testing.expect_value(t, det.obs[0].sig, u64(102))
}
