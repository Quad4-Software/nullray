// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Constrained decoding for tool calls on local providers.

When enabled, requests that carry tools also carry an output constraint the
server enforces at decode time, so a weak local model cannot emit malformed
tool-call JSON. Per-provider mechanism:

  llamacpp      -> top level "grammar" field holding a GBNF grammar (built by
                   tool_grammar_build in tool_grammar.odin). The envelope
                   {"tool_call"/"tool_calls": {name, arguments}} plus
                   {"response": "..."} matches llama.cpp's generic tool parser.
                   Note current llama.cpp rejects grammar+tools with
                   "Cannot specify grammar with tools" because the server now
                   constrains tool calls itself; that rejection is caught once
                   per provider and the field is dropped for the session.

  ollama        -> "response_format" {"type":"json_schema", json_schema:{...}}.
                   Ollama's OpenAI endpoint maps json_schema.schema onto its
                   native format parameter. The schema constrains output to the
                   same tool_calls envelope or {"response": "..."}.

  lmstudio / openai-compat -> same json_schema response_format, both speak the
                   OpenAI structured-outputs shape (xgrammar on vLLM backends).

Gate (all must hold): provider mechanism exists, request carries tools, and
either NULLRAY_CONSTRAINED_TOOLS=1 or the matching model profile sets
"constrained_tools": true. Env 0/false/off forces off outright. A server
rejection that names the constraint field sets Provider.constrained_off so
later requests skip it.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:http"

ENV_CONSTRAINED_TOOLS :: "NULLRAY_CONSTRAINED_TOOLS"

// Error text markers that mean the server rejected the constraint field.
@(private)
CONSTRAINED_REJECT_KEYS :: []string{
	"grammar", "response_format", "json_schema", "json schema",
	"schema", "format", "constrain", "unknown field", "unsupported",
}

Constrained_Mech :: enum {
	None,
	Grammar,
	Json_Schema,
}

constrained_mechanism :: proc(provider_id: string) -> Constrained_Mech {
	switch provider_id {
	case "llamacpp":
		return .Grammar
	case "ollama", "lmstudio", "openai-compat":
		return .Json_Schema
	}
	return .None
}

constrained_tools_enabled :: proc(p: ^Provider, model: string) -> bool {
	if p == nil || p.constrained_off {
		return false
	}
	if constrained_mechanism(p.id) == .None {
		return false
	}
	if v, ok := os.lookup_env(ENV_CONSTRAINED_TOOLS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "", "0", "false", "no", "off", "disable", "disabled":
			return false
		case:
			return true
		}
	}
	if prof, found := profile_for(model); found && prof.constrained_tools_set {
		return prof.constrained_tools
	}
	return false
}

// True when the request will carry a constraint field, mirrors the body write.
constrained_tools_sent :: proc(p: ^Provider, model: string, req: Chat_Request) -> bool {
	return len(req.tools_json) > 0 && constrained_tools_enabled(p, model)
}

// JSON schema envelope for the response_format path: either a tool_calls
// array of {name, arguments} calls or a {"response": "..."} text reply.
@(private)
tool_schema_envelope_json :: proc(tools_json: string, parallel: bool, allocator := context.temp_allocator) -> (string, bool) {
	doc, perr := json.parse_string(tools_json, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return "", false
	}
	arr, ok := doc.(json.Array)
	if !ok || len(arr) == 0 {
		return "", false
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	calls := make([dynamic]string, context.temp_allocator)
	for item in arr {
		to, iok := item.(json.Object)
		if !iok {
			continue
		}
		fnv, fhas := to["function"]
		if !fhas {
			continue
		}
		fn, fok := fnv.(json.Object)
		if !fok {
			continue
		}
		nv, nhas := fn["name"]
		if !nhas {
			continue
		}
		ns, sok := nv.(json.String)
		if !sok || len(ns) == 0 {
			continue
		}
		cb: strings.Builder
		strings.builder_init(&cb, context.temp_allocator)
		strings.write_string(&cb, `{"type":"object","properties":{"name":{"type":"string","const":`)
		write_json_string(&cb, string(ns))
		strings.write_string(&cb, `},"arguments":`)
		if pv, has := fn["parameters"]; has {
			if data, merr := json.marshal(pv, allocator = context.temp_allocator); merr == nil {
				strings.write_string(&cb, string(data))
			} else {
				strings.write_string(&cb, `{}`)
			}
		} else {
			strings.write_string(&cb, `{"type":"object"}`)
		}
		strings.write_string(&cb, `},"required":["name","arguments"],"additionalProperties":false}`)
		append(&calls, strings.to_string(cb))
	}
	if len(calls) == 0 {
		return "", false
	}
	strings.write_string(&b, `{"anyOf":[{"type":"object","properties":{"tool_calls":{"type":"array","items":`)
	if len(calls) == 1 {
		strings.write_string(&b, calls[0])
	} else {
		strings.write_string(&b, `{"anyOf":[`)
		for c, i in calls {
			if i > 0 {
				strings.write_byte(&b, ',')
			}
			strings.write_string(&b, c)
		}
		strings.write_string(&b, `]}`)
	}
	strings.write_string(&b, `,"minItems":1`)
	if !parallel {
		strings.write_string(&b, `,"maxItems":1`)
	}
	strings.write_string(&b, `}},"required":["tool_calls"],"additionalProperties":false}`)
	strings.write_string(&b, `,{"type":"object","properties":{"response":{"type":"string"}},"required":["response"],"additionalProperties":false}]}`)
	return strings.to_string(b), true
}

// Append the provider constraint field for a tools request, if enabled.
write_constrained_tools_json :: proc(b: ^strings.Builder, p: ^Provider, req_p: ^Chat_Request, model: string) {
	if !constrained_tools_enabled(p, model) || len(req_p.tools_json) == 0 {
		return
	}
	parallel := !req_p.parallel_tool_calls_set || req_p.parallel_tool_calls
	switch constrained_mechanism(p.id) {
	case .Grammar:
		if g, ok := tool_grammar_build(req_p.tools_json, parallel, context.temp_allocator); ok {
			strings.write_string(b, `,"grammar":`)
			write_json_string(b, g)
		}
	case .Json_Schema:
		if s, ok := tool_schema_envelope_json(req_p.tools_json, parallel); ok {
			strings.write_string(b, `,"response_format":{"type":"json_schema","json_schema":{"name":"tool_calls","schema":`)
			strings.write_string(b, s)
			strings.write_string(b, `}}`)
		}
	case .None:
	}
}

// True when a failed response looks like the server rejecting the constraint
// field we added: a 4xx/5xx naming grammar, response_format, or schema in the
// error body. Other failures (context length, auth) never match.
constrained_rejected :: proc(res: http.Response) -> bool {
	if res.ok {
		return false
	}
	switch res.status {
	case 400, 404, 405, 406, 409, 413, 415, 422, 500, 501:
	case:
		return false
	}
	text := strings.concatenate({res.err, " ", res.body}, context.temp_allocator)
	low := strings.to_lower(text, context.temp_allocator)
	for kw in CONSTRAINED_REJECT_KEYS {
		if strings.contains(low, kw) {
			return true
		}
	}
	return false
}

// Record the rejection and drop the constraint for the rest of the session.
constrained_disable :: proc(p: ^Provider, res: http.Response) {
	if p == nil || p.constrained_off {
		return
	}
	p.constrained_off = true
	msg := extract_provider_error_message(res.body)
	if len(msg) == 0 {
		msg = res.err
	}
	fmt.eprintf("nullray: %s rejected constrained tool fields (%s); disabling for this session\n", p.id, msg)
}
