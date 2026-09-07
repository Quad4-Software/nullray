// SPDX-License-Identifier: 0BSD
#+build linux
/*
pkexec / polkit: session agent passthrough or clear TUI agent requirement.
*/

package elevate

import "core:os"
import "core:strings"

polkit_session_agent_present :: proc() -> bool {
	if v, ok := os.lookup_env("NULLRAY_POLKIT_AGENT_PRESENT", context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	// Heuristic: graphical session usually has an agent.
	if _, ok := os.lookup_env("DISPLAY", context.temp_allocator); ok {
		return true
	}
	if _, ok := os.lookup_env("WAYLAND_DISPLAY", context.temp_allocator); ok {
		return true
	}
	return false
}

run_pkexec :: proc(cmd: string, cwd: string, allocator := context.allocator) -> Result {
	if !polkit_session_agent_present() {
		// TUI nullray polkit agent: reuse password modal as approval, then attempt pkexec.
		// Without a session D-Bus agent pkexec cannot collect credentials; drive modal then fail clearly
		// if still no agent, unless user already cancelled.
		if secret_ui_enabled() && !headless() {
			_, ok, cancelled := request_password(
				"polkit: approve elevation (desktop agent collects password if present):",
				cmd,
				modal_secs_from_env(),
				context.temp_allocator,
			)
			if cancelled || !ok {
				circuit_record_failure()
				return Result{
					backend = .Pkexec,
					outcome = .Cancelled,
					kind = .Auth_Cancelled,
					exit_code = 1,
					err = strings.clone("auth_cancelled", allocator),
				}
			}
		}
		if !polkit_session_agent_present() {
			return Result{
				backend = .Pkexec,
				outcome = .Polkit_Agent,
				kind = .Polkit_Agent,
				exit_code = 1,
				err = strings.clone(
					"elevation_polkit_agent: no polkit authentication agent; use sudo/doas or start a desktop polkit agent",
					allocator,
				),
			}
		}
	}

	res: Result
	if broker_available() {
		res = broker_run(cmd, cwd, "", "", allocator)
	} else {
		res = exec_capture(cmd, cwd, "", "", allocator)
	}
	res.backend = .Pkexec
	if res.exit_code == 0 {
		res.outcome = .Askpass
		res.kind = .Ok
		circuit_record_success()
		return res
	}
	lower := strings.to_lower(res.stderr, context.temp_allocator)
	if strings.contains(lower, "authentication agent") ||
		strings.contains(lower, "not authorized") ||
		strings.contains(lower, "authorization failed") {
		circuit_record_failure()
		res.outcome = .Polkit_Agent
		res.kind = .Polkit_Agent
		if len(res.err) == 0 {
			res.err = strings.clone("elevation_polkit_agent", allocator)
		}
		return res
	}
	if auth_failure_text(res.stderr) {
		circuit_record_failure()
		res.outcome = .Failed
		res.kind = .Auth_Failed
		return res
	}
	res.outcome = .Failed
	res.kind = .Exec_Failed
	return res
}
