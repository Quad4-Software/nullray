// SPDX-License-Identifier: 0BSD
/*
Shell command safety checks and workspace cwd resolution.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:elevate"
import "nullray:sandbox"

// Always denied even under perms=yolo / gate 3.
ALWAYS_DENIED_SUBSTRINGS :: []string{
	"rm -rf /",
	"rm -rf /*",
	"rm -rf .",
	"rm -rf ./",
	"rm -rf *",
	"mkfs",
	"dd if=",
	":(){",
	"/dev/sd",
	"chmod -R 777 /",
	"> /dev/",
	"curl|bash",
	"curl | bash",
	"curl| bash",
	"curl |bash",
	"wget|sh",
	"wget | sh",
	"wget| sh",
	"wget |sh",
	"shutdown",
	"reboot",
	"mkfs.",
	"/etc/shadow",
	"/etc/passwd",
	".ssh/",
	"id_rsa",
	"id_ed25519",
	"~/.ssh",
	"cat /proc/self/environ",
	"source .env",
	". .env",
	"$OPENROUTER_API_KEY",
	"$OPENAI_API_KEY",
	"$ANTHROPIC_API_KEY",
	"$NULLRAY_API_KEY",
	"$HTTPS_PROXY",
	"$HTTP_PROXY",
	"$ALL_PROXY",
	"systemd-run",
	"busctl ",
	"gdbus ",
	"docker.sock",
	"docker run --privileged",
	"podman run --privileged",
	"git push --force",
	"git push -f ",
	"git push -f",
	"--force-with-lease",
	"drop table",
	"drop database",
	"truncate table",
	"git --output",
	"git checkout --output",
	"git show --output",
}

// Denied under ask/allow only. Yolo skips these so sysadmin benches can run.
STRICT_DENIED_SUBSTRINGS :: []string{
	"printenv",
	"env |",
	"history",
	"chmod 777",
	"chown -R",
	"set -a",
	"$(cat ",
	"`cat ",
	"base64 ",
	"xxd ",
	" hexdump ",
}

shell_command_allowed :: proc(cmd: string, allocator := context.allocator) -> (ok: bool, reason: string) {
	trimmed := strings.trim_space(cmd)
	if len(trimmed) == 0 {
		return false, strings.clone("empty command", allocator)
	}

	if blocked, hint := sandbox.shell_mentions_secret(trimmed); blocked {
		return false, fmt.aprintf(
			"secret path blocked (%s). set NULLRAY_SECRETS_ALLOW to grant access",
			hint,
			allocator = allocator,
		)
	}

	norm := shell_normalize_pipe_spaces(trimmed, context.temp_allocator)
	lower := strings.to_lower(trimmed, context.temp_allocator)
	norm_lower := strings.to_lower(norm, context.temp_allocator)
	for denied in ALWAYS_DENIED_SUBSTRINGS {
		dlow := strings.to_lower(denied, context.temp_allocator)
		if strings.contains(trimmed, denied) ||
		   strings.contains(norm, denied) ||
		   strings.contains(lower, dlow) ||
		   strings.contains(norm_lower, dlow) {
			return false, fmt.aprintf("denied pattern: %s", denied, allocator = allocator)
		}
	}

	if blocked, why := shell_secret_arg_blocked(trimmed); blocked {
		return false, strings.clone(why, allocator)
	}

	if blocked, why := shell_net_blocked(trimmed); blocked {
		return false, strings.clone(why, allocator)
	}

	if blocked, why := shell_docker_gate_blocked(trimmed); blocked {
		return false, strings.clone(why, allocator)
	}

	perms := perms_from_env()
	if perms != .Yolo {
		for denied in STRICT_DENIED_SUBSTRINGS {
			if strings.contains(trimmed, denied) {
				return false, fmt.aprintf("denied pattern: %s", denied, allocator = allocator)
			}
		}
		if shell_is_env_dump(trimmed) {
			return false, strings.clone("denied pattern: bare env dump", allocator)
		}
	}

	if deny_raw, dok := os.lookup_env(constants.ENV_SHELL_DENY, context.temp_allocator); dok && len(deny_raw) > 0 {
		deny_copy := deny_raw
		for extra in strings.split_iterator(&deny_copy, ",") {
			p := strings.trim_space(extra)
			if len(p) == 0 {
				continue
			}
			if strings.contains(trimmed, p) {
				return false, fmt.aprintf("denied pattern: %s", p, allocator = allocator)
			}
		}
	}

	cl := elevate.classify(trimmed)
	if cl.deny_password_args {
		return false, strings.clone(
			"denied: password must not appear in shell args (use nullray elevate UI)",
			allocator,
		)
	}
	if cl.deny_shell || cl.backend == .Su {
		return false, strings.clone("denied: interactive root shells are blocked", allocator)
	}

	if shell_consume_once_allow(trimmed) {
		return true, ""
	}

	if cl.needs {
		shell_set_pending(trimmed)
		return false, strings.clone(
			"pending approval: elevated command requires /allow (password prompt may follow)",
			allocator,
		)
	}

	allow_raw, has_allow := os.lookup_env(constants.ENV_SHELL_ALLOW, context.temp_allocator)
	in_allow := false
	if has_allow && len(allow_raw) > 0 {
		allow_copy := allow_raw
		for prefix in strings.split_iterator(&allow_copy, ",") {
			p := strings.trim_space(prefix)
			if len(p) == 0 {
				continue
			}
			if strings.has_prefix(trimmed, p) {
				in_allow = true
				break
			}
		}
	}

	switch perms {
	case .Yolo:
		return true, ""
	case .Ask:
		if has_allow && len(allow_raw) > 0 && in_allow {
			return true, ""
		}
		shell_set_pending(trimmed)
		return false, strings.clone(
			"pending approval: /allow to run once, /deny to drop, or set NULLRAY_SHELL_ALLOW",
			allocator,
		)
	case .Allow:
		if has_allow && len(allow_raw) > 0 && !in_allow {
			return false, strings.clone("command not in NULLRAY_SHELL_ALLOW list", allocator)
		}
		if confirm, cok := os.lookup_env(constants.ENV_SHELL_CONFIRM, context.temp_allocator); cok && confirm == "1" {
			shell_set_pending(trimmed)
			return false, strings.clone("pending approval: /allow once, or NULLRAY_PERMS=yolo", allocator)
		}
		return true, ""
	}
	return true, ""
}

resolve_cwd_jail :: proc(workspace: string, allocator := context.allocator) -> (abs: string, err: string) {
	clean, cerr := filepath.clean(workspace, context.temp_allocator)
	if cerr != nil {
		clean = workspace
	}
	resolved, aerr := filepath.abs(clean, allocator)
	if aerr != nil {
		return "", fmt.aprintf("resolve workspace failed: %v", aerr, allocator = allocator)
	}
	abs = resolved

	st := sandbox.state()
	if st != nil && st.applied {
		root_src := sandbox.workspace_current()
		if len(root_src) == 0 {
			root_src = st.workspace
		}
		if len(root_src) > 0 {
			root_resolved, rerr := filepath.abs(root_src, context.temp_allocator)
			root := root_src
			if rerr == nil {
				root = root_resolved
			} else {
				root_clean, _ := filepath.clean(root_src, context.temp_allocator)
				root = root_clean
				if !filepath.is_abs(root_clean) {
					root, _ = filepath.abs(root_clean, context.temp_allocator)
				}
			}
			if !sandbox.path_beneath(abs, root) {
				delete(abs)
				return "", strings.clone("workspace outside sandbox allowlist", allocator)
			}
		}
	}
	return abs, ""
}

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
	shell_set_pending(cmd)
	return true, "pending approval: network shell tool needs /allow or NULLRAY_SHELL_NET=1"
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
