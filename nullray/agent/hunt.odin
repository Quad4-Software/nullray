// SPDX-License-Identifier: 0BSD
/*
Bug and vuln hunt profiles: oracles, exploratory, adversarial sampling.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Hunt_Profile :: enum {
	Off,
	Auto,
	Balanced,
	Explore,
	Oracle,
	Adversarial,
}

Hunt_Phase :: enum {
	Explore,
	Oracle,
}

Sampling :: struct {
	temperature:     f64,
	top_p:           f64,
	temperature_set: bool,
	top_p_set:       bool,
}

hunt_profile_from_string :: proc(s: string) -> (Hunt_Profile, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "", "off", "0", "false", "no":
		return .Off, true
	case "auto", "twopass", "two-pass", "2pass":
		return .Auto, true
	case "1", "on", "true", "yes", "hunt":
		return .Auto, true
	case "balanced":
		return .Balanced, true
	case "explore", "exploratory", "creative":
		return .Explore, true
	case "oracle", "confirm", "verify":
		return .Oracle, true
	case "adversarial", "attacker", "redteam", "red-team":
		return .Adversarial, true
	}
	return .Off, false
}

hunt_profile_string :: proc(p: Hunt_Profile) -> string {
	switch p {
	case .Off:
		return "off"
	case .Auto:
		return "auto"
	case .Balanced:
		return "balanced"
	case .Explore:
		return "explore"
	case .Oracle:
		return "oracle"
	case .Adversarial:
		return "adversarial"
	}
	return "off"
}

hunt_from_env :: proc() -> Hunt_Profile {
	if v, ok := os.lookup_env(constants.ENV_HUNT, context.temp_allocator); ok {
		if p, found := hunt_profile_from_string(v); found {
			return p
		}
	}
	return .Off
}

hunt_enabled :: proc(p: Hunt_Profile) -> bool {
	return p != .Off
}

hunt_auto_twopass :: proc(p: Hunt_Profile) -> bool {
	return p == .Auto
}

hunt_phase_from_string :: proc(s: string) -> (Hunt_Phase, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "explore", "exploratory", "1", "phase1":
		return .Explore, true
	case "oracle", "confirm", "2", "phase2":
		return .Oracle, true
	}
	return .Explore, false
}

hunt_phase_string :: proc(p: Hunt_Phase) -> string {
	switch p {
	case .Explore:
		return "explore"
	case .Oracle:
		return "oracle"
	}
	return "explore"
}

hunt_phase_from_env :: proc() -> Hunt_Phase {
	if v, ok := os.lookup_env(constants.ENV_HUNT_PHASE, context.temp_allocator); ok {
		if p, found := hunt_phase_from_string(v); found {
			return p
		}
	}
	return .Explore
}

hunt_set_phase :: proc(phase: Hunt_Phase) {
	os.set_env(constants.ENV_HUNT_PHASE, hunt_phase_string(phase))
}

/*
Preset sampling for hunt profiles. Explicit NULLRAY_TEMPERATURE / NULLRAY_TOP_P win.
Auto uses phase: explore first, oracle second (NULLRAY_HUNT_PHASE).
*/
hunt_preset_sampling :: proc(p: Hunt_Profile) -> Sampling {
	s: Sampling
	switch p {
	case .Off:
		return s
	case .Auto:
		if hunt_phase_from_env() == .Oracle {
			return hunt_preset_sampling(.Oracle)
		}
		return hunt_preset_sampling(.Explore)
	case .Balanced:
		s.temperature = 0.7
		s.top_p = 0.95
		s.temperature_set = true
		s.top_p_set = true
	case .Explore:
		s.temperature = 0.9
		s.top_p = 0.95
		s.temperature_set = true
		s.top_p_set = true
	case .Oracle:
		s.temperature = 0.25
		s.top_p = 0.9
		s.temperature_set = true
		s.top_p_set = true
	case .Adversarial:
		s.temperature = 0.85
		s.top_p = 0.95
		s.temperature_set = true
		s.top_p_set = true
	}
	return s
}

sampling_from_env :: proc(hunt: Hunt_Profile) -> Sampling {
	s := hunt_preset_sampling(hunt)
	if v, ok := os.lookup_env(constants.ENV_TEMPERATURE, context.temp_allocator); ok {
		if n, n_ok := strconv.parse_f64(strings.trim_space(v)); n_ok && n >= 0 && n <= 2 {
			s.temperature = n
			s.temperature_set = true
		}
	}
	if v, ok := os.lookup_env(constants.ENV_TOP_P, context.temp_allocator); ok {
		if n, n_ok := strconv.parse_f64(strings.trim_space(v)); n_ok && n > 0 && n <= 1 {
			s.top_p = n
			s.top_p_set = true
		}
	}
	return s
}

/*
When hunt is on and NULLRAY_REASONING unset, prefer high effort for deeper analysis.
*/
hunt_reasoning_override :: proc(hunt: Hunt_Profile, current: string) -> string {
	if !hunt_enabled(hunt) {
		return current
	}
	if v, ok := os.lookup_env(constants.ENV_REASONING, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return current
	}
	if v, ok := os.lookup_env(constants.ENV_HUNT_REASONING, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return strings.to_lower(strings.trim_space(v), context.temp_allocator)
	}
	return "high"
}

hunt_prompt_block :: proc(p: Hunt_Profile, allocator := context.allocator) -> string {
	if !hunt_enabled(p) {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "\nHunt profile: ")
	strings.write_string(&b, hunt_profile_string(p))
	if p == .Auto {
		strings.write_string(&b, " phase=")
		strings.write_string(&b, hunt_phase_string(hunt_phase_from_env()))
	}
	strings.write_string(&b, " (load_skill bug-hunting).\n")
	lean := prompt_lean_enabled()
	if lean {
		strings.write_string(
			&b,
			"Prefer critical/high impact. Charter → hypothesis → explore/adversarial → oracle-gate. Detail in bug-hunting skill.\n",
		)
	} else {
		strings.write_string(
			&b,
			"Protect open-source users: prefer critical and high impact issues over style.\n",
		)
		strings.write_string(&b, "Protocol:\n")
		strings.write_string(&b, "1. Charter an area (auth, parsers, IPC, supply chain, crypto, sandbox).\n")
		strings.write_string(&b, "2. State a falsifiable hypothesis before deep reading.\n")
		strings.write_string(
			&b,
			"3. Exploratory pass: follow unusual inputs, trust-boundary crossings, and creative misuse.\n",
		)
		strings.write_string(
			&b,
			"4. Adversarial pass: act as an attacker with the least privilege needed to hurt users.\n",
		)
		strings.write_string(
			&b,
			"5. Oracle confirm: each finding needs an independent accept/reject check (repro, invariant, negative test, or unreachable proof). Scanner hits are leads only.\n",
		)
		strings.write_string(
			&b,
			"6. Report only confirmed or strongly evidenced issues. Severity, path:line, attacker control, impact, short repro.\n",
		)
	}
	switch p {
	case .Auto:
		phase := hunt_phase_from_env()
		if phase == .Explore {
			strings.write_string(
				&b,
				"Phase 1 explore: list LEADs and hypotheses. Do not finalize FINDINGS unless already oracle-proven.\n",
			)
		} else {
			strings.write_string(
				&b,
				"Phase 2 oracle: confirm or reject each prior LEAD. Drop rejects. End with FINDINGS: N or FINDINGS: none.\n",
			)
		}
	case .Explore:
		strings.write_string(
			&b,
			"Bias exploratory: more hypotheses and weird paths. Oracle-gate before calling something a finding.\n",
		)
	case .Oracle:
		strings.write_string(
			&b,
			"Bias oracle: kill weak leads fast. Demand repro or unreachable proof.\n",
		)
	case .Adversarial:
		strings.write_string(
			&b,
			"Bias attacker goals: privilege gain, secret theft, supply-chain sabotage, sandbox escape, authz bypass.\n",
		)
	case .Balanced, .Off:
	}
	return strings.to_string(b)
}

// Short user nudge for auto oracle. System prompt already carries phase text.
HUNT_ORACLE_FOLLOWUP :: "Oracle phase: confirm or reject each LEAD above. Report only confirmed issues. End with FINDINGS: N or FINDINGS: none."

sampling_label :: proc(s: Sampling, allocator := context.allocator) -> string {
	if !s.temperature_set && !s.top_p_set {
		return strings.clone("default", allocator)
	}
	if s.temperature_set && s.top_p_set {
		return fmt.aprintf("temp=%.2f top_p=%.2f", s.temperature, s.top_p, allocator = allocator)
	}
	if s.temperature_set {
		return fmt.aprintf("temp=%.2f", s.temperature, allocator = allocator)
	}
	return fmt.aprintf("top_p=%.2f", s.top_p, allocator = allocator)
}

hunt_log_sampling :: proc(profile: Hunt_Profile) {
	if !hunt_enabled(profile) {
		return
	}
	samp := sampling_from_env(profile)
	label := sampling_label(samp, context.temp_allocator)
	if profile == .Auto {
		fmt.eprintf(
			"nullray: hunt auto phase=%s %s\n",
			hunt_phase_string(hunt_phase_from_env()),
			label,
		)
		return
	}
	fmt.eprintf("nullray: hunt %s %s\n", hunt_profile_string(profile), label)
}
