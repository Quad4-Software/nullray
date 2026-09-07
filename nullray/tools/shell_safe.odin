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

DENIED_SUBSTRINGS :: []string{
	"rm -rf /",
	"rm -rf /*",
	"mkfs",
	"dd if=",
	":(){",
	"/dev/sd",
	"chmod -R 777 /",
	"> /dev/",
	"curl|bash",
	"wget|sh",
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
	"printenv",
	"env |",
	"history",
	"chmod 777",
	"chown -R",
	"source .env",
	". .env",
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

	for denied in DENIED_SUBSTRINGS {
		if strings.contains(trimmed, denied) {
			return false, fmt.aprintf("denied pattern: %s", denied, allocator = allocator)
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


	perms := perms_from_env()
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
	if st != nil && st.applied && len(st.workspace) > 0 {
		root_resolved, rerr := filepath.abs(st.workspace, context.temp_allocator)
		root := st.workspace
		if rerr == nil {
			root = root_resolved
		} else {
			root_clean, _ := filepath.clean(st.workspace, context.temp_allocator)
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
	return abs, ""
}
