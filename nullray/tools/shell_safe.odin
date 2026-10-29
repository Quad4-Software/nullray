// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
import "nullray:hooks"
import "nullray:sandbox"
import "nullray:store"

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
	return shell_command_allowed_for(cmd, "run_shell", allocator)
}

shell_command_allowed_for :: proc(
	cmd: string,
	tool_name: string,
	allocator := context.allocator,
) -> (ok: bool, reason: string) {
	ok, reason = shell_command_allowed_inner(cmd, allocator)
	decision := "allow"
	finding := "policy_pass"
	if !ok {
		decision = "block"
		finding = shell_policy_finding(reason)
		if strings.contains(strings.to_lower(reason, context.temp_allocator), "pending approval") ||
		   strings.contains(strings.to_lower(reason, context.temp_allocator), "manual command approval") {
			decision = "approval_required"
		}
	}
	store.audit_log_command(tool_name, cmd, decision, finding)
	return
}

@(private)
shell_policy_finding :: proc(reason: string) -> string {
	lower := strings.to_lower(reason, context.temp_allocator)
	if strings.contains(lower, "metadata") || strings.contains(lower, "reported") || strings.contains(lower, "file-proxy") {
		return "suspicious_endpoint"
	}
	if strings.contains(lower, "host information") || strings.contains(lower, "inventory") || strings.contains(lower, "namespace probing") {
		return "host_information"
	}
	if strings.contains(lower, "verifier") || strings.contains(lower, "command review") || strings.contains(lower, "review unavailable") {
		return "command_verifier"
	}
	if strings.contains(lower, "secret") || strings.contains(lower, "password") {
		return "secret_policy"
	}
	if strings.contains(lower, "network") || strings.contains(lower, "fetch_url") {
		return "network_policy"
	}
	return "shell_policy"
}

@(private)
shell_command_allowed_inner :: proc(cmd: string, allocator := context.allocator) -> (ok: bool, reason: string) {
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

	if why := suspicious_endpoint_reason(trimmed); len(why) > 0 {
		return false, fmt.aprintf("blocked suspicious network endpoint: %s", why, allocator = allocator)
	}
	if why := shell_system_info_reason(trimmed); len(why) > 0 {
		return false, strings.clone(why, allocator)
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

	if handled, reviewed, review_reason := command_verifier_gate(trimmed, "run_shell", allocator); handled {
		if !reviewed {
			return false, review_reason
		}
		delete(review_reason)
	}
	if blocked, why := shell_net_blocked(trimmed); blocked {
		return false, strings.clone(why, allocator)
	}

	if cl.needs {
		if handled, ok2, reason2 := permission_hook_decision("shell", trimmed, allocator); handled {
			return ok2, reason2
		}
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
		if handled, ok2, reason2 := permission_hook_decision("shell", trimmed, allocator); handled {
			return ok2, reason2
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
			if handled, ok2, reason2 := permission_hook_decision("shell", trimmed, allocator); handled {
				return ok2, reason2
			}
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
