// SPDX-License-Identifier: 0BSD
package session

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:tools"

session_clear_streaming :: proc(s: ^Session) {
	strings.builder_reset(&s.streaming)
	s.has_streaming = false
	strings.builder_reset(&s.thinking)
	s.has_thinking = false
}

session_append_delta :: proc(s: ^Session, text: string) {
	cur := strings.builder_len(s.streaming)
	if cur >= constants.MAX_STREAMING_CHARS {
		s.has_streaming = true
		return
	}
	remain := constants.MAX_STREAMING_CHARS - cur
	chunk := text
	if len(chunk) > remain {
		chunk = chunk[:remain]
	}
	strings.write_string(&s.streaming, chunk)
	s.has_streaming = true
}

session_append_thinking :: proc(s: ^Session, text: string) {
	cur := strings.builder_len(s.thinking)
	if cur >= constants.MAX_STREAMING_CHARS {
		s.has_thinking = true
		return
	}
	remain := constants.MAX_STREAMING_CHARS - cur
	chunk := text
	if len(chunk) > remain {
		chunk = chunk[:remain]
	}
	strings.write_string(&s.thinking, chunk)
	s.has_thinking = true
}

session_ready_status :: proc(s: ^Session) -> string {
	mode := agent.mode_string(s.agent_mode)
	perms := tools.perms_string(tools.perms_from_env())
	auto := ""
	if agent.auto_from_env() {
		auto = " auto"
	}
	hide := false
	if v, ok := os.lookup_env(constants.ENV_HIDE_SENSITIVE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "hide":
			hide = true
		}
	}
	if hide || s.last_usage.total_tokens <= 0 {
		return fmt.tprintf("ready · %s · %s%s", mode, perms, auto)
	}
	cost := ""
	if s.last_usage.cost_known && !hide {
		cost = fmt.tprintf(" · $%.4f", s.last_usage.cost_usd)
	}
	return fmt.tprintf(
		"ready · %s · %s%s · %s in / %s out · sess %s%s",
		mode,
		perms,
		auto,
		format_token_count(s.last_usage.prompt_tokens),
		format_token_count(s.last_usage.completion_tokens),
		format_token_count(s.session_usage.total_tokens),
		cost,
	)
}

session_usage_label :: proc(s: ^Session, allocator := context.allocator) -> string {
	if s.last_usage.total_tokens <= 0 && s.session_usage.total_tokens <= 0 {
		return strings.clone("", allocator)
	}
	if s.last_usage.cost_known || s.session_usage.cost_known {
		cost := s.session_usage.cost_usd
		if !s.session_usage.cost_known {
			cost = s.last_usage.cost_usd
		}
		return fmt.aprintf(
			"%s/%s tok · $%.4f",
			format_token_count(s.last_usage.total_tokens),
			format_token_count(s.session_usage.total_tokens),
			cost,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"%s/%s tok",
		format_token_count(s.last_usage.total_tokens),
		format_token_count(s.session_usage.total_tokens),
		allocator = allocator,
	)
}

session_usage_summary_text :: proc(s: ^Session, hide_sensitive: bool, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "turns: %d\n", s.usage_turns)
	fmt.sbprintf(&b, "last: %d in / %d out / %d total", s.last_usage.prompt_tokens, s.last_usage.completion_tokens, s.last_usage.total_tokens)
	if s.last_usage.reasoning_tokens > 0 {
		fmt.sbprintf(&b, " (reasoning %d)", s.last_usage.reasoning_tokens)
	}
	strings.write_byte(&b, '\n')
	fmt.sbprintf(&b, "session: %d prompt / %d completion / %d total", s.session_usage.prompt_tokens, s.session_usage.completion_tokens, s.session_usage.total_tokens)
	if s.session_usage.reasoning_tokens > 0 {
		fmt.sbprintf(&b, " (reasoning %d)", s.session_usage.reasoning_tokens)
	}
	strings.write_byte(&b, '\n')
	fmt.sbprintf(&b, "input_chars: last %d peak %d\n", s.last_input_chars, s.peak_input_chars)
	if s.subagent_total_tokens > 0 {
		fmt.sbprintf(&b, "subagent_tokens: %d\n", s.subagent_total_tokens)
	}
	if hide_sensitive {
		strings.write_string(&b, "cost: hidden\n")
	} else if s.session_usage.cost_known {
		fmt.sbprintf(&b, "cost: $%.6f\n", s.session_usage.cost_usd)
	} else {
		strings.write_string(&b, "cost: unknown\n")
	}
	if len(s.last_stopped) > 0 {
		fmt.sbprintf(&b, "last_stopped: %s\n", s.last_stopped)
	}
	if len(s.model) > 0 {
		fmt.sbprintf(&b, "model: %s\n", s.model)
	}
	if len(s.provider_id) > 0 {
		fmt.sbprintf(&b, "provider: %s\n", s.provider_id)
	}
	return strings.to_string(b)
}

session_usage_summary_json :: proc(s: ^Session, allocator := context.allocator) -> string {
	return fmt.aprintf(
		`{{"turns":%d,"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"cost_usd":%.6f,"cost_known":%v,"peak_input_chars":%d,"last_input_chars":%d,"subagent_total_tokens":%d,"last_prompt_tokens":%d,"last_completion_tokens":%d,"last_total_tokens":%d,"last_cost_usd":%.6f,"last_cost_known":%v,"stopped":%q,"model":%q,"provider":%q}}`,
		s.usage_turns,
		s.session_usage.prompt_tokens,
		s.session_usage.completion_tokens,
		s.session_usage.total_tokens,
		s.session_usage.reasoning_tokens,
		s.session_usage.cost_usd,
		s.session_usage.cost_known,
		s.peak_input_chars,
		s.last_input_chars,
		s.subagent_total_tokens,
		s.last_usage.prompt_tokens,
		s.last_usage.completion_tokens,
		s.last_usage.total_tokens,
		s.last_usage.cost_usd,
		s.last_usage.cost_known,
		s.last_stopped,
		s.model,
		s.provider_id,
		allocator = allocator,
	)
}

@(private)
format_token_count :: proc(n: int) -> string {
	if n < 1000 {
		return fmt.tprintf("%d", n)
	}
	if n < 10_000 {
		return fmt.tprintf("%.1fk", f64(n) / 1000.0)
	}
	return fmt.tprintf("%dk", n / 1000)
}
