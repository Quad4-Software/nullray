// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Harness execution: argv substitution, bounded stdout/stderr capture,
timeout kill, JSON result extraction, and output secret screening.

The prompt never touches a shell: {prompt} is substituted inside one argv
element and passed straight to exec. Binary names come only from the merged
harness table, never from tool args.
*/

package harness

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:hooks"
import "nullray:sandbox"

SECRET_WITHHELD :: "output withheld: likely secret"

Cancel_Check :: proc() -> bool

/*
Load, detect, and run harness id with prompt in workspace. timeout_sec of 0
or less falls back to the harness default (HARNESS_TIMEOUT_SEC), values are
clamped to [1, HARNESS_MAX_TIMEOUT_SEC]. cancel, when non-nil, is polled for
caller interruption.
*/
run :: proc(
	id: string,
	prompt: string,
	workspace: string,
	timeout_sec: int,
	allocator := context.allocator,
	cancel: Cancel_Check = nil,
) -> (output: string, err: string) {
	if !harness_enabled() {
		return "", strings.clone(HARNESS_DISABLED, allocator)
	}
	list := load_harnesses(allocator)
	defer harnesses_destroy(list, allocator)
	detect(list, allocator)
	return run_defined(list, id, prompt, workspace, timeout_sec, allocator, cancel)
}

// run against an already loaded and detected list (tests inject fakes here).
run_defined :: proc(
	list: []Harness,
	id: string,
	prompt: string,
	workspace: string,
	timeout_sec: int,
	allocator := context.allocator,
	cancel: Cancel_Check = nil,
) -> (output: string, err: string) {
	if !harness_enabled() {
		return "", strings.clone(HARNESS_DISABLED, allocator)
	}
	clean_id := strings.trim_space(id)
	if len(clean_id) == 0 {
		return "", strings.clone("engine id required", allocator)
	}
	if len(strings.trim_space(prompt)) == 0 {
		return "", strings.clone("prompt required", allocator)
	}
	h, found := harness_find(list, clean_id)
	if !found {
		return "", fmt.aprintf("unknown harness: %s (see harness_list)", clean_id, allocator = allocator)
	}
	if len(h.binary) == 0 {
		return "", fmt.aprintf("harness %s unavailable: %s not found on PATH", h.id, h.bin, allocator = allocator)
	}
	if len(h.argv) == 0 {
		return "", fmt.aprintf("harness %s has empty argv template", h.id, allocator = allocator)
	}
	eff := timeout_sec
	if eff <= 0 {
		eff = h.timeout_sec
	}
	if eff <= 0 {
		eff = constants.HARNESS_TIMEOUT_SEC
	}
	eff = clamp(eff, 1, constants.HARNESS_MAX_TIMEOUT_SEC)

	argv := make([dynamic]string, context.temp_allocator)
	append(&argv, h.binary)
	for tpl in h.argv {
		append(&argv, substitute_arg(tpl, prompt, workspace, context.temp_allocator))
	}
	env := hooks.hook_env(context.temp_allocator)

	stdout, stderr, exit_code, timed_out, xerr := exec_capture(argv[:], workspace, eff, env, cancel, context.temp_allocator)
	if len(xerr) > 0 {
		return "", strings.clone(xerr, allocator)
	}

	body := stdout
	if h.output == .Json && !timed_out && exit_code == 0 {
		if extracted := extract_json_result(stdout, context.temp_allocator); len(extracted) > 0 {
			body = extracted
		}
	}

	out: strings.Builder
	strings.builder_init(&out, allocator)
	if timed_out {
		fmt.sbprintf(&out, "timeout after %ds\n", eff)
	}
	if exit_code != 0 {
		fmt.sbprintf(&out, "exit_code=%d\n", exit_code)
	}
	if len(body) > 0 {
		strings.write_string(&out, body)
	}
	// stderr rides along on failure so auth/config complaints reach the model.
	if (timed_out || exit_code != 0) && len(strings.trim_space(stderr)) > 0 {
		strings.write_string(&out, "\nstderr: ")
		strings.write_string(&out, stderr)
	}
	result := strings.to_string(out)
	if sandbox.value_looks_secret(result) {
		delete(result, allocator)
		return strings.clone(SECRET_WITHHELD, allocator), ""
	}
	return result, ""
}

/*
Replace {prompt} and {cwd} inside one argv template element in a single pass
so a prompt containing the literal text {cwd} is not rewritten. The result
stays a single argv element regardless of spaces in the prompt.
*/
@(private)
substitute_arg :: proc(tpl: string, prompt: string, cwd: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(tpl) {
		if strings.has_prefix(tpl[i:], "{prompt}") {
			strings.write_string(&b, prompt)
			i += len("{prompt}")
		} else if strings.has_prefix(tpl[i:], "{cwd}") {
			strings.write_string(&b, cwd)
			i += len("{cwd}")
		} else {
			strings.write_byte(&b, tpl[i])
			i += 1
		}
	}
	return strings.to_string(b)
}

// Head/tail bounded capture, keeps first HEAD and last TAIL bytes per stream.
HEAD_KEEP :: constants.HARNESS_MAX_OUTPUT / 2
TAIL_KEEP :: constants.HARNESS_MAX_OUTPUT / 2

@(private)
Cap_Buf :: struct {
	head:  [dynamic]u8,
	tail:  [dynamic]u8,
	total: int,
}

@(private)
cap_buf_init :: proc(b: ^Cap_Buf, allocator := context.temp_allocator) {
	b.head = make([dynamic]u8, allocator)
	b.tail = make([dynamic]u8, allocator)
}

@(private)
cap_buf_push :: proc(b: ^Cap_Buf, data: []u8) {
	if len(data) == 0 {
		return
	}
	b.total += len(data)
	if len(b.head) < HEAD_KEEP {
		remain := HEAD_KEEP - len(b.head)
		take := min(remain, len(data))
		append(&b.head, ..data[:take])
	}
	append(&b.tail, ..data)
	if len(b.tail) > TAIL_KEEP {
		excess := len(b.tail) - TAIL_KEEP
		copy(b.tail[:], b.tail[excess:])
		resize(&b.tail, TAIL_KEEP)
	}
}

@(private)
cap_buf_text :: proc(b: ^Cap_Buf, allocator := context.temp_allocator) -> string {
	if b.total <= len(b.head) {
		// head alone holds the whole stream.
		return strings.clone(string(b.head[:]), allocator)
	}
	tail := b.tail[:]
	// When head and tail overlap (total <= HEAD+TAIL) drop the duplicated
	// middle so the join is exact, the gap, if any, is the omitted count.
	overlap := len(b.head) + len(b.tail) - b.total
	omitted := 0
	if overlap > 0 {
		tail = tail[overlap:]
	} else {
		omitted = -overlap
	}
	if omitted <= 0 {
		return fmt.aprintf("%s%s", string(b.head[:]), string(tail), allocator = allocator)
	}
	return fmt.aprintf(
		"%s\n[... %d bytes omitted ...]\n%s",
		string(b.head[:]),
		omitted,
		string(tail),
		allocator = allocator,
	)
}

// Per-call drain budget: a flooding writer can keep pipe_has_data true
// forever, so each call returns after this many bytes and lets the outer
// loop re-check timeout and cancel.
@(private)
DRAIN_CALL_BUDGET :: 64 * 1024

@(private)
drain_cap :: proc(r: ^os.File, b: ^Cap_Buf, buf: []u8) -> (eof: bool) {
	left := DRAIN_CALL_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return false
		}
		n, rerr := os.read(r, buf)
		if n > 0 {
			cap_buf_push(b, buf[:n])
			left -= n
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			return true
		}
	}
	return false
}

/*
Spawn argv in workspace with stdin closed, capture both streams bounded by
head+tail buffers, kill the process tree on timeout or cancel.
*/
@(private)
exec_capture :: proc(
	argv: []string,
	workspace: string,
	timeout_sec: int,
	env: []string,
	cancel: Cancel_Check,
	allocator := context.allocator,
) -> (stdout: string, stderr: string, exit_code: int, timed_out: bool, err: string) {
	stdout_r, stdout_w, perr0 := os.pipe()
	if perr0 != nil {
		err = fmt.aprintf("pipe failed: %v", perr0, allocator = allocator)
		return
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, perr1 := os.pipe()
	if perr1 != nil {
		os.close(stdout_w)
		err = fmt.aprintf("pipe failed: %v", perr1, allocator = allocator)
		return
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = workspace,
			command     = argv,
			env         = env,
			// nil stdin gives the child a closed input so prompts cannot hang.
			stdout      = stdout_w,
			stderr      = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			err = fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
			return
		}
	}
	harness_claim_process_group(process)

	out_b: Cap_Buf
	cap_buf_init(&out_b)
	err_b: Cap_Buf
	cap_buf_init(&err_b)
	buf: [4096]u8
	timeout := time.Second * time.Duration(timeout_sec)
	start := time.now()
	stdout_done := false
	stderr_done := false
	exited := false

	for !stdout_done || !stderr_done {
		if cancel != nil && cancel() {
			timed_out = true
			kill_process_tree(process)
			break
		}
		if time.since(start) >= timeout {
			timed_out = true
			kill_process_tree(process)
			break
		}
		if !stdout_done {
			stdout_done = drain_cap(stdout_r, &out_b, buf[:])
		}
		if !stderr_done {
			stderr_done = drain_cap(stderr_r, &err_b, buf[:])
		}
		state, werr := os.process_wait(process, 0)
		if werr == nil && state.exited {
			exited = true
			exit_code = state.exit_code
			_ = drain_cap(stdout_r, &out_b, buf[:])
			_ = drain_cap(stderr_r, &err_b, buf[:])
			break
		}
		time.sleep(2 * time.Millisecond)
	}
	if !exited {
		// Timeout and cancel already fired the kill, a pipes-EOF exit with
		// the child still running leaves a blocking wait unbounded. Kill
		// the tree first so the wait is bounded either way.
		kill_process_tree(process)
		state, _ := os.process_wait(process)
		if state.exited {
			exited = true
			exit_code = state.exit_code
		}
	}
	stdout = cap_buf_text(&out_b, allocator)
	stderr = cap_buf_text(&err_b, allocator)
	return
}

/*
Pull a result/output/text string field out of a JSON-mode harness stdout.
Tries the whole body first, then walks lines from the end so JSONL streams
(claude --output-format json style) yield their last object.
*/
@(private)
extract_json_result :: proc(body: string, allocator := context.allocator) -> string {
	trimmed := strings.trim_space(body)
	if len(trimmed) == 0 {
		return ""
	}
	if s := json_result_field(trimmed, context.temp_allocator); len(s) > 0 {
		return strings.clone(s, allocator)
	}
	rest := trimmed
	lines := strings.split(rest, "\n", context.temp_allocator)
	for i := len(lines) - 1; i >= 0; i -= 1 {
		line := strings.trim_space(lines[i])
		if len(line) == 0 || line[0] != '{' {
			continue
		}
		if s := json_result_field(line, context.temp_allocator); len(s) > 0 {
			return strings.clone(s, allocator)
		}
	}
	return ""
}

@(private)
json_result_field :: proc(text: string, allocator := context.allocator) -> string {
	doc, perr := json.parse_string(text, .JSON, allocator = allocator)
	if perr != nil {
		return ""
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return ""
	}
	keys := []string{"result", "output", "text", "response"}
	for key in keys {
		if v, ok := obj[key].(json.String); ok {
			trimmed := strings.trim_space(string(v))
			if len(trimmed) > 0 {
				return trimmed
			}
		}
	}
	return ""
}
