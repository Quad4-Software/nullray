// SPDX-License-Identifier: 0BSD
/*
lc-style gate levels 0..3 for tool capability.
0 read-only, 1 file writes, 2 shell, 3 destructive (always-deny still hard-blocks).
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

gate_parse :: proc(s: string) -> (level: int, ok: bool) {
	trimmed := strings.trim_space(s)
	if n, pok := strconv.parse_int(trimmed); pok && n >= 0 && n <= 3 {
		return n, true
	}
	switch strings.to_lower(trimmed, context.temp_allocator) {
	case "read", "ro", "ask":
		return 0, true
	case "write", "edit":
		return 1, true
	case "shell", "allow":
		return 2, true
	case "full", "yolo", "destructive":
		return 3, true
	}
	return 0, false
}

gate_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_GATE, context.temp_allocator); ok {
		if n, pok := gate_parse(v); pok {
			return n
		}
	}
	// Preserve ask shell-confirm UX: ask/allow both allow shell at gate 2.
	switch perms_from_env() {
	case .Yolo:
		return 3
	case .Ask, .Allow:
		return 2
	}
	return 2
}

gate_string :: proc(g: int) -> string {
	switch g {
	case 0:
		return "0"
	case 1:
		return "1"
	case 2:
		return "2"
	case 3:
		return "3"
	}
	return "2"
}

gate_label :: proc(g: int) -> string {
	switch g {
	case 0:
		return "0 (read)"
	case 1:
		return "1 (write)"
	case 2:
		return "2 (shell)"
	case 3:
		return "3 (destructive)"
	}
	return "2 (shell)"
}

tool_gate_level :: proc(r: ^Registry, name: string) -> int {
	t, found := registry_find(r, name)
	if found && t.gate > 0 {
		return t.gate
	}
	if found {
		switch t.kind {
		case .Read:
			return 0
		case .Write:
			return 1
		case .Shell:
			return 2
		case .Mcp:
			return 2
		}
	}
	if strings.has_prefix(name, "mcp:") {
		return 2
	}
	switch name {
	case "run_shell", "run_script":
		return 2
	case "write_file", "edit_file", "apply_edits", "multi_edit":
		return 1
	}
	return 0
}

gate_allows_tool :: proc(r: ^Registry, name: string) -> (ok: bool, reason: string) {
	need := tool_gate_level(r, name)
	have := gate_from_env()
	if need <= have {
		return true, ""
	}
	return false, fmt.tprintf(
		"tool %s needs gate %d (current %d). raise with --gate / NULLRAY_GATE / /gate",
		name,
		need,
		have,
	)
}

/*
Print and non-interactive runs deny rather than wait for /gate.
*/
gate_auto_deny :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRINT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return !stdin_is_tty()
}
