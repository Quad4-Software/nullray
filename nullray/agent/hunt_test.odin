// SPDX-License-Identifier: 0BSD
package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_hunt_profiles_and_sampling :: proc(t: ^testing.T) {
	p, ok := hunt_profile_from_string("explore")
	testing.expect(t, ok)
	testing.expect(t, p == .Explore)
	s := hunt_preset_sampling(.Explore)
	testing.expect(t, s.temperature_set)
	testing.expect(t, s.temperature >= 0.85)
	s2 := hunt_preset_sampling(.Oracle)
	testing.expect(t, s2.temperature <= 0.3)

	os.unset_env(constants.ENV_HUNT)
	os.unset_env(constants.ENV_HUNT_PHASE)
	os.unset_env(constants.ENV_TEMPERATURE)
	os.unset_env(constants.ENV_TOP_P)
	os.set_env(constants.ENV_HUNT, "adversarial")
	defer os.unset_env(constants.ENV_HUNT)
	testing.expect(t, hunt_from_env() == .Adversarial)
	samp := sampling_from_env(.Adversarial)
	testing.expect(t, samp.temperature_set)
	os.set_env(constants.ENV_TEMPERATURE, "0.4")
	defer os.unset_env(constants.ENV_TEMPERATURE)
	samp2 := sampling_from_env(.Adversarial)
	testing.expect(t, samp2.temperature == 0.4)

	block := hunt_prompt_block(.Oracle, context.temp_allocator)
	testing.expect(t, strings.contains(block, "oracle"))
	testing.expect(t, strings.contains(block, "hypothesis") || strings.contains(block, "bug-hunting"))
}

@(test)
test_hunt_prompt_lean_is_shorter :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PROMPT, "full")
	defer os.unset_env(constants.ENV_PROMPT)
	full := hunt_prompt_block(.Explore, context.allocator)
	defer delete(full)
	os.set_env(constants.ENV_PROMPT, "lean")
	lean := hunt_prompt_block(.Explore, context.allocator)
	defer delete(lean)
	testing.expect(t, len(lean) < len(full))
	testing.expect(t, strings.contains(lean, "bug-hunting"))
	testing.expect(t, !strings.contains(lean, "Protocol:"))
}

@(test)
test_hunt_auto_phase_sampling :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TEMPERATURE)
	os.unset_env(constants.ENV_TOP_P)
	os.set_env(constants.ENV_HUNT, "auto")
	defer os.unset_env(constants.ENV_HUNT)
	testing.expect(t, hunt_from_env() == .Auto)
	testing.expect(t, hunt_auto_twopass(.Auto))

	hunt_set_phase(.Explore)
	s1 := sampling_from_env(.Auto)
	testing.expect(t, s1.temperature >= 0.85)

	hunt_set_phase(.Oracle)
	s2 := sampling_from_env(.Auto)
	testing.expect(t, s2.temperature <= 0.3)

	block := hunt_prompt_block(.Auto, context.temp_allocator)
	testing.expect(t, strings.contains(block, "phase 2") || strings.contains(block, "oracle"))
	os.unset_env(constants.ENV_HUNT_PHASE)
}

@(test)
test_hunt_on_means_auto :: proc(t: ^testing.T) {
	p, ok := hunt_profile_from_string("1")
	testing.expect(t, ok)
	testing.expect(t, p == .Auto)
	p2, ok2 := hunt_profile_from_string("balanced")
	testing.expect(t, ok2)
	testing.expect(t, p2 == .Balanced)
}
