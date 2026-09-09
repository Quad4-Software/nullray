// SPDX-License-Identifier: 0BSD
/*
OpenRouter provider routing, fallback models, and rate-limit helpers.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:http"

OpenRouter_ZDR_Mode :: enum {
	Off,
	Warn,
	Require,
}

@(private)
openrouter_zdr_warned: bool

openrouter_zdr_reset_for_test :: proc() {
	openrouter_zdr_warned = false
}

// Effective ZDR mode for chat routing. Non-openrouter providers always return Off.
openrouter_zdr_effective :: proc(provider_id: string) -> OpenRouter_ZDR_Mode {
	if provider_id != "openrouter" {
		return .Off
	}
	return openrouter_zdr_mode_from_env()
}

@(private)
openrouter_zdr_mode_from_env :: proc() -> OpenRouter_ZDR_Mode {
	v, ok := os.lookup_env(constants.ENV_OPENROUTER_ZDR, context.temp_allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		return .Warn
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "off", "0", "false", "no", "disable", "disabled":
		return .Off
	case "require", "strict", "on", "1", "true", "yes":
		return .Require
	case "warn", "default":
		return .Warn
	}
	return .Warn
}

@(private)
openrouter_zdr_data_collection_deny :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_OPENROUTER_DATA_COLLECTION, context.temp_allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		return true
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "allow", "off", "0", "false", "no", "disable", "disabled":
		return false
	case "deny", "on", "1", "true", "yes":
		return true
	}
	return true
}

// One-time stderr note when ZDR is not enforced on OpenRouter chat requests.
openrouter_zdr_maybe_warn :: proc(provider_id: string) {
	if provider_id != "openrouter" || openrouter_zdr_warned {
		return
	}
	if openrouter_zdr_effective(provider_id) != .Warn {
		return
	}
	openrouter_zdr_warned = true
	fmt.eprintf(
		"nullray: OpenRouter ZDR not enforced (NULLRAY_OPENROUTER_ZDR=warn); set require for zero-data-retention routing\n",
	)
}

http_retry_limit :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_HTTP_RETRIES, context.temp_allocator); ok {
		n, nok := strconv.parse_int(strings.trim_space(v))
		if nok && n >= 0 {
			return n
		}
	}
	return constants.HTTP_RETRIES_DEFAULT
}

http_status_retryable :: proc(status: int) -> bool {
	return status == 429 || status == 502 || status == 503 || status == 504 || status == 529
}

retry_wait :: proc(attempt: int, retry_after_sec: int) {
	sec := retry_after_sec
	if sec <= 0 {
		sec = 1 << uint(min(attempt, 4))
	}
	if sec > 30 {
		sec = 30
	}
	ms := sec * 1000
	for ms > 0 {
		if http.cancel_requested() {
			return
		}
		slice := min(ms, 200)
		time.sleep(time.Millisecond * time.Duration(slice))
		ms -= slice
	}
}

// Append OpenRouter provider routing and model fallbacks before the closing brace.
write_openrouter_extras :: proc(b: ^strings.Builder, ignore: []string) {
	mode := openrouter_zdr_mode_from_env()
	strings.write_string(b, `,"provider":{"allow_fallbacks":true`)
	if mode == .Require {
		strings.write_string(b, `,"zdr":true`)
		if openrouter_zdr_data_collection_deny() {
			strings.write_string(b, `,"data_collection":"deny"`)
		}
	}
	merged := merge_openrouter_ignore(ignore, context.temp_allocator)
	if len(merged) > 0 {
		strings.write_string(b, `,"ignore":[`)
		for name, i in merged {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			write_json_string(b, name)
		}
		strings.write_byte(b, ']')
	}
	strings.write_string(b, `}`)

	fallbacks := openrouter_fallback_models(context.temp_allocator)
	if len(fallbacks) > 0 {
		strings.write_string(b, `,"models":[`)
		for m, i in fallbacks {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			write_json_string(b, m)
		}
		strings.write_byte(b, ']')
	}
}

openrouter_fallback_models :: proc(allocator := context.temp_allocator) -> []string {
	v, ok := os.lookup_env(constants.ENV_FALLBACK_MODELS, allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		return nil
	}
	return split_csv_trim(v, allocator)
}

merge_openrouter_ignore :: proc(extra: []string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	seen: map[string]bool
	defer delete(seen)

	add :: proc(out: ^[dynamic]string, seen: ^map[string]bool, name: string) {
		n := strings.trim_space(name)
		if len(n) == 0 {
			return
		}
		key := strings.to_lower(n, context.temp_allocator)
		if seen[key] {
			return
		}
		seen[key] = true
		append(out, n)
	}

	if v, ok := os.lookup_env(constants.ENV_OPENROUTER_IGNORE, context.temp_allocator); ok {
		for part in split_csv_trim(v, context.temp_allocator) {
			add(&out, &seen, part)
		}
	}
	for name in extra {
		add(&out, &seen, name)
	}
	return out[:]
}

// Pull provider_name values from an OpenRouter error body for ignore on retry.
extract_openrouter_rate_limit_providers :: proc(body: string, allocator := context.allocator) -> []string {
	if len(body) == 0 {
		return nil
	}
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return nil
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return nil
	}
	err_v, has := obj["error"]
	if !has {
		return nil
	}
	err_obj, eok := err_v.(json.Object)
	if !eok {
		return nil
	}
	names := make([dynamic]string, context.temp_allocator)
	if meta_v, mok := err_obj["metadata"]; mok {
		if meta, mok2 := meta_v.(json.Object); mok2 {
			if pn, pok := meta["provider_name"]; pok {
				if s, sok := pn.(json.String); sok {
					append(&names, string(s))
				}
			}
			if prev, pok := meta["previous_errors"]; pok {
				if arr, aok := prev.(json.Array); aok {
					for item in arr {
						if pe, peok := item.(json.Object); peok {
							if pn, pok2 := pe["provider_name"]; pok2 {
								if s, sok := pn.(json.String); sok {
									append(&names, string(s))
								}
							}
						}
					}
				}
			}
		}
	}
	out := make([dynamic]string, allocator)
	seen: map[string]bool
	defer delete(seen)
	for name in names {
		n := strings.trim_space(name)
		if len(n) == 0 {
			continue
		}
		key := strings.to_lower(n, context.temp_allocator)
		if seen[key] {
			continue
		}
		seen[key] = true
		append(&out, strings.clone(n, allocator))
	}
	return out[:]
}

openrouter_rate_limit_hint :: proc(body: string, allocator := context.allocator) -> string {
	providers := extract_openrouter_rate_limit_providers(body, context.temp_allocator)
	if len(providers) == 0 {
		return strings.clone(
			"HTTP 429 rate limited upstream. Retry shortly, set NULLRAY_FALLBACK_MODELS, or add a provider key at openrouter.ai/settings/integrations",
			allocator,
		)
	}
	joined := strings.join(providers, ", ", context.temp_allocator)
	return fmt.aprintf(
		"HTTP 429 rate limited on %s. Retried with provider ignore when possible. Set NULLRAY_FALLBACK_MODELS or a BYOK key at openrouter.ai/settings/integrations",
		joined,
		allocator = allocator,
	)
}

@(private)
split_csv_trim :: proc(v: string, allocator := context.temp_allocator) -> []string {
	parts := strings.split(v, ",", context.temp_allocator)
	out := make([dynamic]string, allocator)
	for p in parts {
		t := strings.trim_space(p)
		if len(t) > 0 {
			append(&out, strings.clone(t, allocator))
		}
	}
	return out[:]
}
