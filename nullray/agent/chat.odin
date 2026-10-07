// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Single chat call with optional streaming bridge and provider failover.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:provider"

Delta_Ctx :: struct {
	cfg:     Config,
	harness: ^Harness_Metrics,
}

@(private)
delta_bridge :: proc(kind: provider.Delta_Kind, text: string, user: rawptr) {
	ctx := cast(^Delta_Ctx)user
	switch kind {
	case .Content:
		emit(ctx.cfg, .Delta, text)
	case .Reasoning:
		emit(ctx.cfg, .Reasoning_Delta, text)
	}
}

@(private)
run_one_chat :: proc(
	p: ^provider.Provider,
	msgs: []provider.Message,
	model, tools_json: string,
	cfg: Config,
	harness: ^Harness_Metrics,
	allocator := context.allocator,
) -> provider.Chat_Response {
	choice := ""
	if len(tools_json) > 0 {
		choice = "auto"
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = cfg.stream,
		tools_json = tools_json,
		tool_choice = choice,
		reasoning_effort = cfg.reasoning_effort,
		max_tokens = cfg.max_tokens,
		temperature = cfg.temperature,
		top_p = cfg.top_p,
		temperature_set = cfg.temperature_set,
		top_p_set = cfg.top_p_set,
		session_id = cfg.session_id,
	}
	provider.apply_gguf_tool_sampling(&req, p.id, model, tools_json)
	if cfg.stream {
		if p.stream == nil {
			return provider.Chat_Response{
				ok = false,
				err = strings.clone("streaming not supported by this provider", allocator),
			}
		}
		dctx := Delta_Ctx{cfg = cfg, harness = harness}
		if cfg.speculate_pool != nil {
			req.on_tool_seal = tool_seal_bridge
			req.seal_user = &dctx
		}
		res := p.stream(p, req, delta_bridge, &dctx, allocator)
		if !res.ok {
			err := res.err
			if len(err) == 0 {
				err = strings.clone("chat failed", allocator)
			} else {
				err = strings.clone(err, allocator)
			}
			provider.destroy_chat_response(&res)
			return provider.Chat_Response{ok = false, err = err}
		}
		provider.apply_quirks(&res, model, allocator)
		return res
	}
	res := p.chat(p, req)
	if !res.ok {
		err := res.err
		if len(err) == 0 {
			err = strings.clone("chat failed", allocator)
		} else {
			err = strings.clone(err, allocator)
		}
		provider.destroy_chat_response(&res)
		return provider.Chat_Response{ok = false, err = err}
	}
	provider.apply_quirks(&res, model, allocator)
	return res
}

@(private)
single_chat :: proc(
	p: ^provider.Provider,
	msgs: []provider.Message,
	model, tools_json: string,
	cfg: Config,
	harness: ^Harness_Metrics = nil,
	allocator := context.allocator,
) -> provider.Chat_Response {
	// AgentDiet plus CORVUS pass: prune a cloned list per request. Session
	// history in msgs is never mutated; the dieted copy dies with this call.
	send := msgs
	dieted: [dynamic]provider.Message
	used_diet := false
	if diet_enabled() || corvus_enabled() {
		d, st := diet_messages(msgs, allocator)
		changed := st.stubbed > 0 || st.truncated > 0 || st.corvus.stubbed > 0 || st.corvus.state_entries > 0
		if changed && len(d) > 0 && diet_pairing_ok(d[:]) {
			dieted = d
			send = d[:]
			used_diet = true
			saved := st.chars_before - st.chars_after
			if harness != nil {
				harness.diet_saved_chars += st.diet_saved
				harness.corvus_saved_chars += st.corvus.saved_chars
			}
			if st.corvus.stubbed > 0 || st.corvus.state_entries > 0 {
				emit(cfg, .Status, fmt.tprintf(
					"diet: %d stubbed %d truncated, corvus: %d stubbed state:%d files, -%d chars",
					st.stubbed, st.truncated, st.corvus.stubbed, st.corvus.state_entries, saved))
			} else {
				emit(cfg, .Status, fmt.tprintf("diet: %d stubbed %d truncated -%d chars", st.stubbed, st.truncated, saved))
			}
		} else {
			provider.destroy_messages(d[:])
			delete(d)
		}
	}
	defer if used_diet {
		provider.destroy_messages(dieted[:])
		delete(dieted)
	}
	res := run_one_chat(p, send, model, tools_json, cfg, harness, allocator)
	if !res.ok && used_diet && diet_err_looks_shape(res.err) {
		// A shape rejection should not happen after pairing validation, but
		// retry once with full history rather than lose the request.
		provider.destroy_chat_response(&res)
		emit(cfg, .Status, "diet: request rejected, retrying full history")
		res = run_one_chat(p, msgs, model, tools_json, cfg, harness, allocator)
	}
	if res.ok || !provider.chat_is_failover_worthy(res.err) {
		return res
	}
	fallbacks := provider.provider_fallback_ids()
	if len(fallbacks) == 0 {
		return res
	}
	primary_err := res.err
	primary_id := p.id
	why_label := provider.failover_why_label(provider.failover_why_from_err(primary_err))
	for id in fallbacks {
		if id == primary_id {
			continue
		}
		alt, ok := provider.make_provider_by_id(id)
		if !ok {
			continue
		}
		if !provider.provider_ready_for_chat(&alt) {
			provider.provider_destroy(&alt)
			continue
		}
		emit(cfg, .Status, fmt.tprintf("failover: trying %s after %s %s failure", id, primary_id, why_label))
		// Keep the requested model when it is a plain local name. Swap only when the
		// primary id looks cloud-scoped (vendor/model) and the fallback has a default.
		alt_model := model
		if strings.contains(model, "/") && len(alt.default_model) > 0 {
			alt_model = alt.default_model
		}
		// Failover uses non-stream for reliability across providers.
		cfg2 := cfg
		cfg2.stream = false
		cfg2.speculate_pool = nil
		try := run_one_chat(&alt, send, alt_model, tools_json, cfg2, harness, allocator)
		provider.provider_destroy(&alt)
		if try.ok {
			delete(primary_err)
			note := provider.failover_note(primary_id, id, why_label, context.temp_allocator)
			emit(cfg, .Status, note)
			return try
		}
		provider.destroy_chat_response(&try)
		delete(try.err)
	}
	combined := fmt.aprintf(
		"%s (no working provider in NULLRAY_PROVIDER_FALLBACKS)",
		primary_err,
		allocator = allocator,
	)
	delete(primary_err)
	return provider.Chat_Response{ok = false, err = combined}
}

@(private)
clone_messages :: proc(msgs: []provider.Message, allocator := context.allocator) -> [dynamic]provider.Message {
	out := make([dynamic]provider.Message, 0, len(msgs), allocator)
	for m in msgs {
		append(&out, provider.clone_message(m, allocator))
	}
	return out
}
