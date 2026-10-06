// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Shell policy: pipe normalization, env-dump and net-egress detection,
permission hook decisions, secret args, docker gate.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:hooks"
import "nullray:sandbox"

@(private)
shell_normalize_pipe_spaces :: proc(cmd: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(cmd) {
		if cmd[i] == '|' {
			strings.write_byte(&b, '|')
			i += 1
			for i < len(cmd) && cmd[i] == ' ' {
				i += 1
			}
			continue
		}
		if cmd[i] == ' ' {
			j := i
			for j < len(cmd) && cmd[j] == ' ' {
				j += 1
			}
			if j < len(cmd) && cmd[j] == '|' {
				i = j
				continue
			}
		}
		strings.write_byte(&b, cmd[i])
		i += 1
	}
	return strings.to_string(b)
}

@(private)
shell_is_env_dump :: proc(cmd: string) -> bool {
	fields := strings.fields(cmd, context.temp_allocator)
	if len(fields) == 0 {
		return false
	}
	if fields[0] == "env" {
		// `env` alone or `env | …` already covered. Allow `env FOO=bar cmd`.
		if len(fields) == 1 {
			return true
		}
		for f in fields[1:] {
			if !strings.contains(f, "=") {
				return true
			}
		}
	}
	return false
}

@(private)
shell_net_env_ok :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SHELL_NET, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on", "allow":
			return true
		}
	}
	return false
}

@(private)
shell_looks_net_egress :: proc(cmd: string) -> bool {
	lower := strings.to_lower(cmd, context.temp_allocator)
	fields := strings.fields(lower, context.temp_allocator)
	if len(fields) == 0 {
		return false
	}
	base := fields[0]
	if strings.contains(base, "/") {
		base = filepath.base(base)
	}
	switch base {
	case "curl", "wget", "nc", "ncat", "netcat", "socat":
		return true
	}
	return false
}

@(private)
shell_net_blocked :: proc(cmd: string) -> (blocked: bool, reason: string) {
	if !shell_looks_net_egress(cmd) {
		return false, ""
	}
	if shell_net_env_ok() {
		return false, ""
	}
	if shell_consume_once_allow(cmd) {
		return false, ""
	}
	if handled, ok2, reason2 := permission_hook_decision("shell", cmd, context.temp_allocator); handled {
		return !ok2, reason2
	}
	shell_set_pending(cmd)
	return true, "pending approval: network shell tool needs /allow or NULLRAY_SHELL_NET=1"
}

/*
A PermissionRequest hook may answer a pending shell approval in place of the
human prompt: {"decision":"allow"} or {"decision":"deny","reason":"..."} on
stdout. A deny also fires the PermissionDenied notification event. No answer
means the normal /allow pending flow applies.
*/
@(private)
permission_hook_decision :: proc(
	tool_name, detail: string,
	allocator := context.allocator,
) -> (handled: bool, allowed: bool, reason: string) {
	res := hooks.run(.PermissionRequest, tool_name, detail, allocator)
	if len(res.decision) == 0 {
		hooks.result_destroy(&res, allocator)
		return false, false, ""
	}
	allowed = res.decision == "allow"
	if !allowed {
		if len(res.reason) > 0 {
			reason = strings.clone(res.reason, allocator)
		} else {
			reason = strings.clone("denied by PermissionRequest hook", allocator)
		}
		denied := hooks.run(.PermissionDenied, tool_name, detail, context.temp_allocator)
		hooks.result_destroy(&denied, context.temp_allocator)
	}
	hooks.result_destroy(&res, allocator)
	return true, allowed, reason
}

@(private)
shell_secret_arg_blocked :: proc(cmd: string) -> (blocked: bool, reason: string) {
	if sandbox.value_looks_secret(cmd) {
		return true, "secret-shaped shell args blocked"
	}
	lower := strings.to_lower(cmd, context.temp_allocator)
	markers := []string{"sk-", "api_key=", "apikey=", "authorization: bearer", "-----begin "}
	for m in markers {
		if strings.contains(lower, m) {
			return true, "secret-shaped shell args blocked"
		}
	}
	return false, ""
}

@(private)
shell_docker_gate_blocked :: proc(cmd: string) -> (blocked: bool, reason: string) {
	lower := strings.to_lower(cmd, context.temp_allocator)
	mentions := strings.contains(lower, "docker") || strings.contains(lower, "podman")
	if !mentions {
		return false, ""
	}
	sock_grant := strings.contains(lower, "docker.sock")
	if !sock_grant {
		cfg := sandbox.config_from_env()
		defer sandbox.config_destroy(&cfg)
		for p in cfg.extra_sock {
			if strings.contains(p, "docker.sock") {
				sock_grant = true
				break
			}
		}
	}
	if !sock_grant {
		return false, ""
	}
	if gate_from_env() >= 3 {
		return false, ""
	}
	return true, "docker/podman with socket grant needs gate 3 (--gate 3 / NULLRAY_GATE=3)"
}
