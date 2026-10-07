// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Self-reflective tool error envelopes (arxiv 2606.05037) and failed-call
descriptions (arxiv 2608.23651). On small models a verbatim failed call
replayed in the transcript makes re-emission more likely, so failures are
recorded as structure instead of echoing the raw arguments. Gate:
NULLRAY_FAILURE_DESC=0 disables, default on.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "nullray:constants"

FAIL_ARG_VALUE_MAX :: 48
FAIL_ARG_KEYS_MAX :: 8
FAIL_SUMMARY_MAX :: 240

failure_desc_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_FAILURE_DESC, context.temp_allocator); ok {
		lv := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		return lv != "0" && lv != "off" && lv != "false"
	}
	return true
}

/*
Call-formation errors must reach the agent-side malformed classifier with
their original prefixes, so run never wraps them in the envelope. Mirrors
malformed_call_class in package agent.
*/
err_is_call_formation :: proc(err: string) -> bool {
	if strings.has_prefix(err, "unknown tool") {
		return true
	}
	if strings.has_prefix(err, "tool not runnable") {
		return true
	}
	if strings.has_prefix(err, "bad tool args JSON") {
		return true
	}
	if strings.has_prefix(err, "tool args must be a JSON object") {
		return true
	}
	return false
}

/*
Wrap a tool error in the keyed envelope when the flag allows. Returns the
input unchanged for call-formation errors so retry classification keeps
working. Frees the input error when a wrapped string replaces it.
*/
run_fail :: proc(name, args_json, err: string, allocator := context.allocator) -> string {
	if len(err) == 0 {
		return err
	}
	if !failure_desc_enabled() || err_is_call_formation(err) {
		return err
	}
	wrapped := error_envelope(name, args_json, err, allocator)
	delete(err)
	return wrapped
}

/*
Collapse an error body to a single line capped at max chars.
*/
fail_single_line :: proc(s: string, max: int, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	limit := len(s)
	if limit > max {
		limit = max
	}
	for i in 0 ..< limit {
		c := s[i]
		if c == '\r' || c == '\n' || c == '\t' || c < 0x20 {
			strings.write_byte(&b, ' ')
			continue
		}
		strings.write_byte(&b, c)
	}
	out := strings.to_string(b)
	if len(s) > max {
		return fmt.aprintf("%s...", out, allocator = allocator)
	}
	return out
}

/*
Structural summary of call arguments: key=value for short scalars, a size
marker for long values. Never returns the raw JSON so a failed call cannot
be echoed verbatim back into the transcript.
*/
arg_key_summary :: proc(args_json: string, allocator := context.allocator) -> string {
	doc, perr := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return ""
	}
	obj, ok := doc.(json.Object)
	if !ok || len(obj) == 0 {
		return ""
	}
	keys := make([dynamic]string, 0, len(obj), context.temp_allocator)
	for k in obj {
		append(&keys, k)
	}
	slice.sort_by(keys[:], proc(a, b: string) -> bool { return strings.compare(a, b) < 0 })
	parts := make([dynamic]string, 0, len(keys), context.temp_allocator)
	for k in keys {
		if len(parts) >= FAIL_ARG_KEYS_MAX {
			append(&parts, "...")
			break
		}
		v := obj[k]
		s := "?"
		switch val in v {
		case json.String:
			sv := fail_single_line(string(val), FAIL_ARG_VALUE_MAX)
			if len(val) <= FAIL_ARG_VALUE_MAX {
				s = sv
			} else {
				s = fmt.tprintf("<%d bytes>", len(val))
			}
		case json.Integer:
			s = fmt.tprintf("%v", val)
		case json.Float:
			s = fmt.tprintf("%v", val)
		case json.Boolean:
			s = "true" if bool(val) else "false"
		case json.Null:
			s = "null"
		case json.Array:
			s = fmt.tprintf("<array[%d]>", len(val))
		case json.Object:
			s = fmt.tprintf("<object[%d]>", len(val))
		}
		append(&parts, fmt.tprintf("%s=%s", k, s))
	}
	out := strings.join(parts[:], ", ", context.temp_allocator)
	if len(out) > FAIL_SUMMARY_MAX {
		out = out[:FAIL_SUMMARY_MAX]
	}
	return strings.clone(out, allocator)
}

/*
Walk up from path until a directory that exists. Falls back to the
workspace root so the alternative is always admissible.
*/
nearest_existing_parent :: proc(path: string, allocator := context.allocator) -> string {
	dir := resolve_path(path, context.temp_allocator)
	for i := 0; i < 32; i += 1 {
		if len(dir) == 0 {
			break
		}
		if os.is_directory(dir) {
			return strings.clone(dir, allocator)
		}
		parent := filepath.dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return workspace_root(allocator)
}

/*
Keyed error envelope: what failed, the observed value, and admissible
alternatives. Small keyed text, not JSON.
*/
error_envelope :: proc(name, args_json, err_text: string, allocator := context.allocator) -> string {
	why := fail_single_line(err_text, FAIL_SUMMARY_MAX)
	lower := strings.to_lower(err_text, context.temp_allocator)
	path_arg, _ := json_arg_string_optional(args_json, "path", "", context.temp_allocator)
	cmd_arg, _ := json_arg_string_optional(args_json, "command", "", context.temp_allocator)

	observed := ""
	alternatives := ""
	switch {
	case strings.contains(lower, "old_string not found"):
		if len(path_arg) > 0 {
			observed = fmt.tprintf("no match for old_string in %s", path_arg)
			alternatives = fmt.tprintf(
				"grep_files to locate the target text, read_file %s and rebuild old_string from current content",
				path_arg,
			)
		} else {
			observed = "no match for old_string"
			alternatives = "grep_files to locate the target text, read_file the file again and rebuild old_string"
		}
	case name == "run_shell" &&
	     (strings.contains(lower, "exec failed") ||
	      strings.contains(lower, "enoent") ||
	      strings.contains(lower, "no such file")):
		observed = fail_single_line(cmd_arg, 120)
		alternatives = "list_dir to inspect the workspace, verify the program name or path, then retry"
	case len(path_arg) > 0 &&
	     (strings.contains(lower, "read failed") ||
	      strings.contains(lower, "list failed") ||
	      strings.contains(lower, "enoent") ||
	      strings.contains(lower, "no such file") ||
	      strings.contains(lower, "not found") ||
	      strings.contains(lower, "does not exist")):
		parent := nearest_existing_parent(path_arg, context.temp_allocator)
		observed = path_arg
		alternatives = fmt.tprintf("list_dir path=%s, glob_files to locate the intended file", parent)
	}
	if len(observed) == 0 {
		summary := arg_key_summary(args_json, context.temp_allocator)
		if len(summary) > 0 {
			observed = summary
		} else {
			observed = "none"
		}
	}
	if len(alternatives) == 0 {
		alternatives = "correct the arguments and retry, or continue without this tool"
	}
	return fmt.aprintf("error: %s\nobserved: %s\nalternatives: %s", why, observed, alternatives, allocator = allocator)
}

/*
Recorded form for a failed call: tool <name> failed: <why> (<arg keys>).
When the error already carries an envelope its observed and alternatives
lines ride along. The raw arguments JSON is never included.
*/
describe_tool_failure :: proc(name, args_json, err_text: string, allocator := context.allocator) -> string {
	why := fail_single_line(err_text, FAIL_SUMMARY_MAX)
	extra := ""
	if strings.has_prefix(err_text, "error:") {
		if nl := strings.index_byte(err_text, '\n'); nl >= 0 {
			why = strings.trim_space(strings.clone(err_text[len("error:"):nl], context.temp_allocator))
			extra = err_text[nl + 1:]
		} else {
			why = strings.trim_space(strings.clone(err_text[len("error:"):], context.temp_allocator))
		}
	}
	keys := arg_key_summary(args_json, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "tool %s failed", name)
	if len(why) > 0 {
		fmt.sbprintf(&b, ": %s", why)
	}
	if len(keys) > 0 {
		fmt.sbprintf(&b, " (%s)", keys)
	}
	if len(extra) > 0 {
		fmt.sbprintf(&b, "\n%s", extra)
	}
	return strings.to_string(b)
}
