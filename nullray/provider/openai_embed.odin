// SPDX-License-Identifier: 0BSD
/*
OpenAI-compatible embeddings (local hosts and cloud).
*/

package provider

import "core:encoding/json"
import "core:math"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:http"

Embed_Data_Row :: struct {
	index:  int,
	vector: []f32,
}

openai_embed :: proc(p: ^Provider, req: Embed_Request, allocator := context.allocator) -> Embed_Response {
	if p == nil || len(p.base_url) == 0 {
		return Embed_Response{
			ok = false,
			err = strings.clone("provider base URL missing for embeddings", allocator),
		}
	}
	if len(req.input) == 0 {
		return Embed_Response{ok = false, err = strings.clone("empty embed input", allocator)}
	}
	for s in req.input {
		if len(strings.trim_space(s)) == 0 {
			return Embed_Response{ok = false, err = strings.clone("blank embed input", allocator)}
		}
	}
	model := req.model
	if len(model) == 0 {
		model = default_embed_model_for_provider(p.id)
	}
	if len(model) == 0 {
		return Embed_Response{
			ok = false,
			err = strings.clone("NULLRAY_EMBED_MODEL required for this provider", allocator),
		}
	}
	if p.id == "openrouter" {
		openrouter_zdr_maybe_warn(p.id)
	}

	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	url := http.join_url(p.base_url, "/embeddings")
	body := build_openai_embed_body(model, req.input)
	last := http.post_json(url, headers[:], body, constants.RAG_EMBED_TIMEOUT_SEC, context.temp_allocator)
	if !last.ok {
		if last.status == 404 && p.id == "ollama" {
			return ollama_native_embed(p, model, req.input, allocator)
		}
		err := provider_http_error(last, p, allocator)
		return Embed_Response{ok = false, err = err}
	}
	return parse_openai_embed_response(last.body, allocator)
}

build_openai_embed_body :: proc(model: string, inputs: []string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	strings.write_string(&b, `,"encoding_format":"float","input":`)
	if len(inputs) == 1 {
		write_json_string(&b, inputs[0])
	} else {
		strings.write_byte(&b, '[')
		for s, i in inputs {
			if i > 0 {
				strings.write_byte(&b, ',')
			}
			write_json_string(&b, s)
		}
		strings.write_byte(&b, ']')
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

parse_openai_embed_response :: proc(body: string, allocator := context.allocator) -> Embed_Response {
	doc, parse_err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return Embed_Response{ok = false, err = strings.clone("embed response JSON parse failed", allocator)}
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return Embed_Response{ok = false, err = strings.clone("embed response not an object", allocator)}
	}
	if err_v, has_err := obj["error"]; has_err {
		if err_obj, eok := err_v.(json.Object); eok {
			if msg, mok := err_obj["message"]; mok {
				if s, sok := msg.(json.String); sok {
					return Embed_Response{ok = false, err = strings.clone(string(s), allocator)}
				}
			}
		}
		return Embed_Response{ok = false, err = strings.clone("embed API error", allocator)}
	}
	model_out := ""
	if mv, mok := obj["model"]; mok {
		if s, sok := mv.(json.String); sok {
			model_out = strings.clone(string(s), allocator)
		}
	}
	data_v, has_data := obj["data"]
	if !has_data {
		delete(model_out)
		return Embed_Response{ok = false, err = strings.clone("embed response missing data", allocator)}
	}
	arr, aok := data_v.(json.Array)
	if !aok || len(arr) == 0 {
		delete(model_out)
		return Embed_Response{ok = false, err = strings.clone("embed response empty data", allocator)}
	}

	rows := make([dynamic]Embed_Data_Row, context.temp_allocator)
	for item in arr {
		row_obj, rok := item.(json.Object)
		if !rok {
			continue
		}
		idx := len(rows)
		if iv, iok := row_obj["index"]; iok {
			#partial switch n in iv {
			case json.Integer:
				idx = int(n)
			case json.Float:
				idx = int(n)
			}
		}
		ev, eok := row_obj["embedding"]
		if !eok {
			continue
		}
		earr, eaok := ev.(json.Array)
		if !eaok {
			continue
		}
		vec, verr := json_array_to_f32(earr, allocator)
		if len(verr) > 0 {
			for r in rows {
				delete(r.vector)
			}
			delete(model_out)
			return Embed_Response{ok = false, err = strings.clone(verr, allocator)}
		}
		append(&rows, Embed_Data_Row{index = idx, vector = vec})
	}
	if len(rows) == 0 {
		delete(model_out)
		return Embed_Response{ok = false, err = strings.clone("no embeddings in response", allocator)}
	}
	max_idx := 0
	for r in rows {
		if r.index > max_idx {
			max_idx = r.index
		}
	}
	n := max(len(rows), max_idx + 1)
	out := make([][]f32, n, allocator)
	for r in rows {
		if r.index < 0 || r.index >= n {
			delete(r.vector)
			continue
		}
		if out[r.index] != nil {
			delete(out[r.index])
		}
		out[r.index] = r.vector
	}
	for v in out {
		if v == nil {
			destroy_embed_vectors(out)
			delete(model_out)
			return Embed_Response{ok = false, err = strings.clone("embed batch missing index", allocator)}
		}
	}
	dim := len(out[0])
	for v in out {
		if len(v) != dim {
			destroy_embed_vectors(out)
			delete(model_out)
			return Embed_Response{ok = false, err = strings.clone("embed dim mismatch in batch", allocator)}
		}
		if vector_is_zero(v) {
			destroy_embed_vectors(out)
			delete(model_out)
			return Embed_Response{ok = false, err = strings.clone("embed returned zero vector", allocator)}
		}
	}
	return Embed_Response{ok = true, model = model_out, vectors = out}
}

json_array_to_f32 :: proc(arr: json.Array, allocator := context.allocator) -> ([]f32, string) {
	if len(arr) == 0 {
		return nil, "empty embedding"
	}
	out := make([]f32, len(arr), allocator)
	for item, i in arr {
		#partial switch n in item {
		case json.Float:
			out[i] = f32(n)
		case json.Integer:
			out[i] = f32(n)
		case:
			delete(out)
			return nil, "non-numeric embedding component"
		}
	}
	return out, ""
}

vector_is_zero :: proc(v: []f32) -> bool {
	for x in v {
		if x != 0 && !math.is_nan(x) {
			return false
		}
	}
	return true
}

destroy_embed_vectors :: proc(vecs: [][]f32) {
	for v in vecs {
		delete(v)
	}
	delete(vecs)
}

ollama_native_embed :: proc(
	p: ^Provider,
	model: string,
	inputs: []string,
	allocator := context.allocator,
) -> Embed_Response {
	root := openai_compat_root(p.base_url, context.temp_allocator)
	url := http.join_url(root, "/api/embed")
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	strings.write_string(&b, `,"input":`)
	if len(inputs) == 1 {
		write_json_string(&b, inputs[0])
	} else {
		strings.write_byte(&b, '[')
		for s, i in inputs {
			if i > 0 {
				strings.write_byte(&b, ',')
			}
			write_json_string(&b, s)
		}
		strings.write_byte(&b, ']')
	}
	strings.write_byte(&b, '}')
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	last := http.post_json(
		url,
		headers[:],
		strings.to_string(b),
		constants.RAG_EMBED_TIMEOUT_SEC,
		context.temp_allocator,
	)
	if !last.ok {
		err := provider_http_error(last, p, allocator)
		return Embed_Response{ok = false, err = err}
	}
	return parse_ollama_native_embed(last.body, model, allocator)
}

parse_ollama_native_embed :: proc(body, model: string, allocator := context.allocator) -> Embed_Response {
	doc, parse_err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return Embed_Response{ok = false, err = strings.clone("ollama embed JSON parse failed", allocator)}
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return Embed_Response{ok = false, err = strings.clone("ollama embed not an object", allocator)}
	}
	ev, eok := obj["embeddings"]
	if !eok {
		return Embed_Response{ok = false, err = strings.clone("ollama embed missing embeddings", allocator)}
	}
	arr, aok := ev.(json.Array)
	if !aok || len(arr) == 0 {
		return Embed_Response{ok = false, err = strings.clone("ollama embed empty", allocator)}
	}
	out := make([][]f32, len(arr), allocator)
	for item, i in arr {
		inner, iok := item.(json.Array)
		if !iok {
			destroy_embed_vectors(out)
			return Embed_Response{ok = false, err = strings.clone("ollama embed row not array", allocator)}
		}
		vec, verr := json_array_to_f32(inner, allocator)
		if len(verr) > 0 {
			destroy_embed_vectors(out)
			return Embed_Response{ok = false, err = strings.clone(verr, allocator)}
		}
		if vector_is_zero(vec) {
			delete(vec)
			destroy_embed_vectors(out)
			return Embed_Response{ok = false, err = strings.clone("embed returned zero vector", allocator)}
		}
		out[i] = vec
	}
	return Embed_Response{ok = true, model = strings.clone(model, allocator), vectors = out}
}

default_embed_model_for_provider :: proc(id: string) -> string {
	if v, ok := os.lookup_env(constants.ENV_EMBED_MODEL, context.temp_allocator); ok {
		trimmed := strings.trim_space(v)
		if len(trimmed) > 0 {
			return trimmed
		}
	}
	switch id {
	case "ollama":
		return constants.DEFAULT_EMBED_MODEL_OLLAMA
	case "openrouter":
		return constants.DEFAULT_EMBED_MODEL_OPENROUTER
	case "openai", "openai-compat", "azure":
		return constants.DEFAULT_EMBED_MODEL_OPENAI
	}
	return ""
}
