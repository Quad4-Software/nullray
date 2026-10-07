// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
SWE-Protege escalation: the base model drives, a stronger backend takes
exactly one chat call when the loop detector reports distress (a stall
verdict from a repeated warn), then control returns to the base model.
The escalation target comes from NULLRAY_ESCALATE_MODEL in provider/model
form, or a bare model name to stay on the same provider. When the head of
the spec is not a known provider id the whole value is treated as a model
name, so openrouter-style ids keep working.

Failure on the escalation backend degrades silently back to the base
model for that step, same spirit as provider failover. Escalations are
capped per turn session (NULLRAY_ESCALATE_MAX, default 3) and a signature
that already triggered one escalation never triggers another.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

Escalate_Target :: struct {
	provider_id: string, // empty stays on the base provider
	model:       string, // empty falls back to the target default
}

Escalate_Make_Proc :: #type proc(id: string) -> (provider.Provider, bool)

Escalate_State :: struct {
	armed:     bool,
	target:    Escalate_Target,
	max:       int,
	used:      int,   // scheduled escalations, the cap applies here
	fired:     int,   // escalated calls that actually ran
	pending:   bool,  // next chat call escalates once
	marks:     Loop_Marks, // signatures that already consumed an escalation
	label:     string,     // last "provider/model" used, for reporting
}

// Tests override this to inject a fake escalation backend without env.
@(private)
g_escalate_make: Escalate_Make_Proc

escalate_make_provider :: proc(id: string) -> (provider.Provider, bool) {
	if g_escalate_make != nil {
		return g_escalate_make(id)
	}
	return provider.make_provider_by_id(id)
}

escalate_max_from_env :: proc() -> int {
	n := constants.ESCALATE_MAX_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_ESCALATE_MAX, context.temp_allocator); ok {
		if parsed, pok := strconv.parse_int(strings.trim_space(v)); pok {
			n = parsed
		}
	}
	if n < 0 {
		n = 0
	}
	if n > constants.ESCALATE_MAX_CAP {
		n = constants.ESCALATE_MAX_CAP
	}
	return n
}

// Parse NULLRAY_ESCALATE_MODEL. provider/model splits on the first slash
// when the head is a usable provider id, anything else is a model name on
// the base provider. Empty or unset disarms escalation.
escalate_target_from_env :: proc(allocator := context.temp_allocator) -> (target: Escalate_Target, ok: bool) {
	v, found := os.lookup_env(constants.ENV_ESCALATE_MODEL, context.temp_allocator)
	if !found {
		return {}, false
	}
	spec := strings.trim_space(v)
	if len(spec) == 0 {
		return {}, false
	}
	if idx := strings.index(spec, "/"); idx > 0 {
		head := provider.normalize_provider_id(spec[:idx])
		if made, mok := escalate_make_provider(head); mok {
			// Head resolves to a real provider: split and keep the model tail.
			provider.provider_destroy(&made)
			target.provider_id = head
			target.model = strings.clone(strings.trim_space(spec[idx + 1:]), allocator)
			return target, true
		}
	}
	target.model = strings.clone(spec, allocator)
	return target, true
}

/*
Arm a fresh per-turn escalation state. armed=false when no target is
configured, which makes escalate_should always decline. Owns target.model
and label under allocator, escalate_state_destroy frees them.
*/
escalate_state_init :: proc(allocator := context.allocator) -> Escalate_State {
	target, ok := escalate_target_from_env(allocator)
	return Escalate_State{
		armed = ok,
		target = target,
		max = escalate_max_from_env(),
	}
}

escalate_state_destroy :: proc(st: ^Escalate_State) {
	if st == nil {
		return
	}
	delete(st.target.model)
	delete(st.label)
	st^ = {}
}

/*
verdict to escalation mapping: a stall verdict schedules one escalated
chat call unless the cap is hit or this signature already consumed an
escalation. Scheduling counts against the cap so a failing backend cannot
burn the budget by re-arming.
*/
escalate_should :: proc(st: ^Escalate_State, stall: bool, sig: u64) -> bool {
	if st == nil || !st.armed || !stall {
		return false
	}
	if st.pending || st.used >= st.max {
		return false
	}
	if loop_marks_has(&st.marks, sig) {
		return false
	}
	loop_marks_add(&st.marks, sig)
	st.used += 1
	st.pending = true
	return true
}

/*
Resolve the escalation backend for one call. When the target has no
provider id the base provider answers with the override model, otherwise a
fresh provider is made into alt (caller owns it when alt is returned via p
== alt and must provider_destroy). A target that resolves to the same
model on the same provider is not an escalation.
*/
escalate_pick :: proc(
	target: Escalate_Target,
	base: ^provider.Provider,
	base_model: string,
	alt: ^provider.Provider,
) -> (p: ^provider.Provider, model: string, ok: bool) {
	if len(target.provider_id) == 0 {
		if len(target.model) == 0 || target.model == base_model {
			return nil, "", false
		}
		return base, target.model, true
	}
	made, mok := escalate_make_provider(target.provider_id)
	if !mok {
		return nil, "", false
	}
	if !provider.provider_ready_for_chat(&made) {
		provider.provider_destroy(&made)
		return nil, "", false
	}
	m := target.model
	if len(m) == 0 {
		m = made.default_model
	}
	if len(m) == 0 || (made.id == base.id && m == base_model) {
		provider.provider_destroy(&made)
		return nil, "", false
	}
	alt^ = made
	return alt, m, true
}

escalate_label :: proc(provider_id, model: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/%s", provider_id, model, allocator = allocator)
}

/*
One chat step with the SWE-Protege escalation hook. When the detector
scheduled an escalation this call runs against the escalation backend
with the same context, non-streamed like provider failover, then control
returns to the base model for the next step. A failed escalation call
degrades silently back to the base model for this step.
*/
escalate_chat_step :: proc(
	base: ^provider.Provider,
	msgs: []provider.Message,
	model, tools_json: string,
	cfg: Config,
	esc: ^Escalate_State,
	harness: ^Harness_Metrics,
	allocator := context.allocator,
) -> provider.Chat_Response {
	if esc == nil || !esc.pending {
		return single_chat(base, msgs, model, tools_json, cfg, harness, allocator)
	}
	esc.pending = false
	alt: provider.Provider
	p, esc_model, ok := escalate_pick(esc.target, base, model, &alt)
	if !ok {
		return single_chat(base, msgs, model, tools_json, cfg, harness, allocator)
	}
	esc.fired += 1
	delete(esc.label)
	esc.label = escalate_label(p.id, esc_model, allocator)
	emit(cfg, .Status, fmt.tprintf("escalate: %s on %s after loop stall", esc_model, p.id))
	esc_cfg := cfg
	esc_cfg.stream = false
	esc_cfg.speculate_pool = nil
	res := single_chat(p, msgs, esc_model, tools_json, esc_cfg, harness, allocator)
	provider.provider_destroy(&alt)
	if res.ok {
		return res
	}
	emit(cfg, .Status, "escalate: backend failed, back to base model")
	provider.destroy_chat_response(&res)
	return single_chat(base, msgs, model, tools_json, cfg, harness, allocator)
}
