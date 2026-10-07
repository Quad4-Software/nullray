// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Extensible run judge: asks a decision model whether the agent actually
finished the task, for QA gating and --print-strict.

Two backend kinds, selected by NULLRAY_JUDGE:

  off            disabled (default when unset would otherwise fire nothing)
  auto           jev when a usable key is present, chat when the active
                 provider is local, else off
  jev[:MODEL[@URL]]
                 System One style decision API (Jev and compatible
                 implementations). POST {url}/systemone with a noul
                 question, read back the yes-probability.
  laya[:MODEL[@URL]]
                 Alias for jev aimed at a local laya-serve instance
                 (default http://127.0.0.1:8000/v1, model laya).
  chat[:MODEL[@URL]]
                 Any OpenAI-compatible chat endpoint used as a verdict
                 model. Defaults to the active provider, @URL points it at a
                 different server (for example a second llama.cpp running a
                 small judge-tuned model).

NULLRAY_JUDGE_KEY overrides the backend key. NULLRAY_JUDGE_CONFIDENCE sets
the yes-probability treated as done (default 0.7). NULLRAY_JUDGE_RETRY=1
escalates a failed run through NULLRAY_PROVIDER_FALLBACKS, nudging the
session until a judge pass or the ladder is exhausted.
*/

package provider

import "core:encoding/json"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:http"

ENV_JUDGE :: "NULLRAY_JUDGE"
ENV_JUDGE_KEY :: "NULLRAY_JUDGE_KEY"
ENV_JUDGE_CONFIDENCE :: "NULLRAY_JUDGE_CONFIDENCE"
ENV_JUDGE_RETRY :: "NULLRAY_JUDGE_RETRY"

JUDGE_DEFAULT_URL_JEV :: "https://opencode.ai/zen/v1"
JUDGE_DEFAULT_MODEL_JEV :: "jev-1.13"
JUDGE_DEFAULT_URL_LAYA :: "http://127.0.0.1:8000/v1"
JUDGE_DEFAULT_MODEL_LAYA :: "laya"

Judge_Kind :: enum {
	Off,
	Jev,
	Chat,
}

Judge_Config :: struct {
	kind:      Judge_Kind,
	url:       string,
	key:       string,
	model:     string,
	threshold: f64,
}

judge_config_from_env :: proc(active: ^Provider = nil) -> Judge_Config {
	cfg := Judge_Config{kind = .Off, threshold = 0.7}
	if v, ok := os.lookup_env(ENV_JUDGE_CONFIDENCE, context.temp_allocator); ok {
		if f, fok := strconv.parse_f64(strings.trim_space(v)); fok && f > 0 && f <= 1 {
			cfg.threshold = f
		}
	}
	v, ok := os.lookup_env(ENV_JUDGE_KEY, context.temp_allocator)
	if ok {
		cfg.key = v
	}

	raw, has_raw := os.lookup_env(ENV_JUDGE, context.temp_allocator)
	spec := has_raw ? strings.to_lower(strings.trim_space(raw), context.temp_allocator) : "off"
	if spec == "" {
		spec = "auto"
	}
	kind := spec
	rest := ""
	if i := strings.index(spec, ":"); i >= 0 {
		kind = spec[:i]
		rest = spec[i + 1:]
	}
	model, url := rest, ""
	if i := strings.index(rest, "@"); i >= 0 {
		model = rest[:i]
		url = rest[i + 1:]
	}

	switch kind {
	case "off", "0", "false", "no":
		return cfg
	case "jev":
		cfg.kind = .Jev
	case "laya":
		// Local laya-serve speaks the same systemone API.
		cfg.kind = .Jev
		if len(url) == 0 {
			url = JUDGE_DEFAULT_URL_LAYA
		}
		if len(model) == 0 {
			model = JUDGE_DEFAULT_MODEL_LAYA
		}
	case "chat":
		cfg.kind = .Chat
	case "auto", "on", "1", "true", "yes":
		if jev_key_available() {
			cfg.kind = .Jev
		} else if active != nil && provider_is_local(active.id) {
			cfg.kind = .Chat
		} else {
			return cfg
		}
	case:
		return cfg
	}

	if len(url) > 0 {
		cfg.url = strings.trim_right(url, "/")
	} else if cfg.kind == .Jev {
		cfg.url = JUDGE_DEFAULT_URL_JEV
	} else if active != nil {
		cfg.url = strings.trim_right(active.base_url, "/")
	}
	if len(model) > 0 {
		cfg.model = model
	} else if cfg.kind == .Jev {
		cfg.model = JUDGE_DEFAULT_MODEL_JEV
	} else if active != nil {
		cfg.model = active.default_model
	}
	if len(cfg.key) == 0 {
		if cfg.kind == .Jev && cfg.url == JUDGE_DEFAULT_URL_JEV {
			cfg.key = judge_jev_key()
		} else if cfg.kind == .Chat && active != nil {
			cfg.key = active.api_key
		}
	}
	return cfg
}

judge_enabled :: proc(cfg: Judge_Config) -> bool {
	return cfg.kind != .Off && len(cfg.url) > 0 && len(cfg.model) > 0
}

@(private)
judge_jev_key :: proc() -> string {
	envs := []string{constants.ENV_OPENCODE_KEY, "TYPESAFE_API_KEY", constants.ENV_API_KEY}
	for env in envs {
		if v, ok := os.lookup_env(env, context.temp_allocator); ok && len(v) > 0 {
			return v
		}
	}
	return ""
}

@(private)
jev_key_available :: proc() -> bool {
	return len(judge_jev_key()) > 0
}

/*
Ask the judge whether task is demonstrably done given the agent's result.
Returns the yes-probability in [0,1], whether the call succeeded, and an error.
*/
judge_score_done :: proc(
	cfg: ^Judge_Config,
	active: ^Provider,
	task: string,
	result: string,
	allocator := context.allocator,
) -> (prob: f64, ok: bool, err: string) {
	if cfg == nil || !judge_enabled(cfg^) {
		return 0, false, ""
	}
	#partial switch cfg.kind {
	case .Jev:
		return judge_jev_score(cfg, task, result, allocator)
	case .Chat:
		return judge_chat_score(cfg, active, task, result, allocator)
	}
	return 0, false, ""
}

@(private)
judge_state :: proc(task, result: string, allocator: mem.Allocator) -> string {
	tail := result
	if len(tail) > 4000 {
		tail = tail[len(tail) - 4000:]
	}
	return fmt.aprintf("TASK: %s\n\nAGENT RESULT: %s", task, tail, allocator = allocator)
}

@(private)
judge_jev_score :: proc(
	cfg: ^Judge_Config,
	task, result: string,
	allocator: mem.Allocator,
) -> (f64, bool, string) {
	state := judge_state(task, result, context.temp_allocator)
	body := fmt.aprintf(
		`{{"state":%q,"model":%q,"questions":{{"done":{{"type":"noul","instructions":"Did the agent fully complete the task described in TASK? Say yes only when the result demonstrates the work was actually performed and is correct, not merely described or proposed.","criteria":{{"true":"Task demonstrably completed correctly","false":"Task incomplete, wrong, or only described"}}}}}}}}`,
		state,
		cfg.model,
		allocator = context.temp_allocator,
	)
	headers := make([dynamic]string, context.temp_allocator)
	append(&headers, "Content-Type: application/json")
	if len(cfg.key) > 0 {
		append(&headers, fmt.aprintf("Authorization: Bearer %s", cfg.key, allocator = context.temp_allocator))
	}
	url := fmt.aprintf("%s/systemone", cfg.url, allocator = context.temp_allocator)
	res := http.post_json(url, headers[:], body, 30, context.temp_allocator)
	if res.err != "" {
		return 0, false, strings.clone(res.err, allocator)
	}
	obj, perr := json.parse_string(res.body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return 0, false, strings.clone("judge: bad systemone response", allocator)
	}
	root, rok := obj.(json.Object)
	if !rok {
		return 0, false, strings.clone("judge: bad systemone response", allocator)
	}
	answers, aok := root["answers"].(json.Object)
	if !aok {
		return 0, false, strings.clone("judge: missing answers", allocator)
	}
	done, dok := answers["done"].(json.Object)
	if !dok {
		return 0, false, strings.clone("judge: missing done answer", allocator)
	}
	score: f64 = -1
	#partial switch n in done["noul"] {
	case json.Float:
		score = f64(n)
	case json.Integer:
		score = f64(n)
	}
	if score < 0 {
		return 0, false, strings.clone("judge: no noul score", allocator)
	}
	return score, true, ""
}

@(private)
judge_chat_score :: proc(
	cfg: ^Judge_Config,
	active: ^Provider,
	task, result: string,
	allocator: mem.Allocator,
) -> (f64, bool, string) {
	jp: ^Provider
	owned: Provider
	if active != nil && (len(cfg.url) == 0 || cfg.url == strings.trim_right(active.base_url, "/")) {
		jp = active
	} else {
		owned = make_openai_compat(cfg.url, cfg.key, cfg.model)
		defer provider_destroy(&owned)
		jp = &owned
	}
	if jp == nil || jp.chat == nil {
		return 0, false, strings.clone("judge: no chat backend", allocator)
	}
	msgs := []Message{
		{
			role = .System,
			content = `You are a strict completion judge. Reply with exactly one JSON object {"done":true} or {"done":false} and nothing else.`,
		},
		{
			role = .User,
			content = fmt.aprintf(
				"%s\n\nReply {{\"done\":true}} only if the agent actually completed the task correctly (files changed/answers given), not if it only described or proposed work.",
				judge_state(task, result, context.temp_allocator),
				allocator = context.temp_allocator,
			),
		},
	}
	// Reasoning models spend part of the budget on thinking before emitting
	// the verdict, so give the judge room. The response must land on the
	// caller allocator: openai_chat ends the shared temp epoch on return,
	// which would free fields cloned there.
	res := jp.chat(jp, Chat_Request{
		model = cfg.model,
		messages = msgs,
		max_tokens = 1024,
		temperature = 0,
		temperature_set = true,
	}, allocator)
	defer {
		delete(res.err)
		delete(res.content)
		delete(res.reasoning)
		delete(res.finish_reason)
		delete(res.model)
		destroy_tool_calls_owned(res.tool_calls)
	}
	if res.err != "" {
		return 0, false, strings.clone(res.err, allocator)
	}
	if d, ok := os.lookup_env("NULLRAY_DEBUG", context.temp_allocator); ok && d == "judge" {
		fmt.eprintfln("judge chat raw content=%q reasoning=%q", res.content, res.reasoning)
	}
	if prob, ok, _ := judge_parse_verdict(res.content, allocator); ok {
		return prob, ok, ""
	}
	// Reasoning models may put the verdict in the reasoning channel.
	return judge_parse_verdict(res.reasoning, allocator)
}

@(private)
judge_parse_verdict :: proc(content: string, allocator: mem.Allocator) -> (f64, bool, string) {
	// Models may wrap the JSON in prose or a code fence, find a done boolean
	// anywhere in the payload.
	obj, perr := json.parse_string(content, .JSON, allocator = context.temp_allocator)
	if perr == .None {
		if o, ok := obj.(json.Object); ok {
			if b, bok := o["done"].(json.Boolean); bok {
				if b {
					return 1, true, ""
				}
				return 0, true, ""
			}
		}
	}
	if s := strings.index(content, "{"); s >= 0 {
		if e := strings.last_index(content, "}"); e > s {
			inner := content[s:e + 1]
			obj2, perr2 := json.parse_string(inner, .JSON, allocator = context.temp_allocator)
			if perr2 == .None {
				if o, ok := obj2.(json.Object); ok {
					if b, bok := o["done"].(json.Boolean); bok {
						if b {
							return 1, true, ""
						}
						return 0, true, ""
					}
				}
			}
		}
	}
	low := strings.to_lower(content, context.temp_allocator)
	switch {
	case strings.contains(low, `"done":true`), strings.contains(low, `"done": true`):
		return 1, true, ""
	case strings.contains(low, `"done":false`), strings.contains(low, `"done": false`):
		return 0, true, ""
	case strings.contains(low, `"done":yes`), strings.contains(low, `"done": yes`):
		return 1, true, ""
	case strings.contains(low, `"done":no`), strings.contains(low, `"done": no`):
		return 0, true, ""
	}
	return 0, false, strings.clone("judge: unparseable verdict", allocator)
}
