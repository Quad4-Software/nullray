/*
OpenRouter account credits and API-key limit helpers.
Docs: GET /api/v1/credits (account), GET /api/v1/key (per-key limit).
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:http"

OpenRouter_Balance :: struct {
	ok:                 bool,
	total_credits:      f64,
	total_usage:        f64,
	remaining:          f64,
	has_account:        bool,
	key_limit:          f64,
	key_limit_remaining: f64,
	has_key_limit:      bool,
	label:              string,
	err:                string,
}

openrouter_headers :: proc(api_key: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	append(&out, "Content-Type: application/json")
	if len(api_key) > 0 {
		append(&out, fmt.aprintf("Authorization: Bearer %s", api_key, allocator = allocator))
	}
	append(&out, "HTTP-Referer: https://github.com/Quad4-Software/nullray")
	append(&out, fmt.aprintf("X-Title: %s", constants.APP_NAME, allocator = allocator))
	return out[:]
}

openrouter_fetch_balance :: proc(api_key: string, allocator := context.allocator) -> OpenRouter_Balance {
	out: OpenRouter_Balance
	if len(api_key) == 0 {
		out.err = strings.clone("missing OPENROUTER_API_KEY", allocator)
		return out
	}
	headers := openrouter_headers(api_key)

	key_url := http.join_url(constants.DEFAULT_OPENROUTER_BASE, "/key")
	key_res := http.get(key_url, headers, 20, context.temp_allocator)
	if key_res.ok {
		parse_openrouter_key_body(key_res.body, &out)
	}

	cred_url := http.join_url(constants.DEFAULT_OPENROUTER_BASE, "/credits")
	cred_res := http.get(cred_url, headers, 20, context.temp_allocator)
	if cred_res.ok {
		parse_openrouter_credits_body(cred_res.body, &out)
	} else if !out.has_key_limit {
		out.err = strings.clone(cred_res.err, allocator)
		if len(out.err) == 0 {
			out.err = strings.clone("credits request failed", allocator)
		}
		return out
	}

	out.ok = out.has_account || out.has_key_limit
	if out.has_account {
		out.remaining = out.total_credits - out.total_usage
	}
	return out
}

openrouter_balance_label :: proc(b: OpenRouter_Balance, allocator := context.allocator) -> string {
	if !b.ok {
		if len(b.err) > 0 {
			return strings.clone(b.err, allocator)
		}
		return strings.clone("credits n/a", allocator)
	}
	parts: [dynamic]string
	parts.allocator = context.temp_allocator
	if b.has_account {
		append(&parts, fmt.tprintf("acct $%.2f", b.remaining))
	}
	if b.has_key_limit {
		append(&parts, fmt.tprintf("key $%.2f", b.key_limit_remaining))
	}
	if len(parts) == 0 {
		return strings.clone("credits n/a", allocator)
	}
	return strings.clone(strings.join(parts[:], " · ", context.temp_allocator), allocator)
}

@(private)
parse_openrouter_credits_body :: proc(body: string, out: ^OpenRouter_Balance) {
	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return
	}
	root, rok := doc.(json.Object)
	if !rok {
		return
	}
	data_v, dok := root["data"]
	if !dok {
		return
	}
	data, ok := data_v.(json.Object)
	if !ok {
		return
	}
	out.total_credits = json_float_field(data, "total_credits")
	out.total_usage = json_float_field(data, "total_usage")
	out.has_account = true
}

@(private)
parse_openrouter_key_body :: proc(body: string, out: ^OpenRouter_Balance) {
	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return
	}
	root, rok := doc.(json.Object)
	if !rok {
		return
	}
	data_v, dok := root["data"]
	if !dok {
		return
	}
	data, ok := data_v.(json.Object)
	if !ok {
		return
	}
	if lv, lok := data["limit"]; lok {
		if _, is_null := lv.(json.Null); !is_null {
			out.key_limit = json_float_value(lv)
			out.has_key_limit = true
		}
	}
	if rv, rok2 := data["limit_remaining"]; rok2 {
		if _, is_null := rv.(json.Null); !is_null {
			out.key_limit_remaining = json_float_value(rv)
			out.has_key_limit = true
		}
	}
}

@(private)
json_float_field :: proc(obj: json.Object, key: string) -> f64 {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	return json_float_value(v)
}

@(private)
json_float_value :: proc(v: json.Value) -> f64 {
	#partial switch n in v {
	case json.Float:
		return f64(n)
	case json.Integer:
		return f64(n)
	}
	return 0
}
