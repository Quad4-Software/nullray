// SPDX-License-Identifier: 0BSD
/*
Per-thread workspace override for worktree subagents.
*/

package sandbox

import "core:os"
import "core:strings"
import "nullray:constants"

@(thread_local)
tls_workspace_override: string

/*
Set the workspace used by tools for this thread. Caller must clear.
*/
workspace_override_set :: proc(ws: string) {
	delete(tls_workspace_override)
	tls_workspace_override = {}
	if len(ws) > 0 {
		tls_workspace_override = strings.clone(ws)
	}
}

workspace_override_clear :: proc() {
	delete(tls_workspace_override)
	tls_workspace_override = {}
}

/*
Effective workspace: thread override, sandbox state, NULLRAY_WORKSPACE, else empty.
Returned string is not owned when it comes from TLS or state. Env fallback is
temp_allocator-backed for the duration of the caller's frame.
*/
workspace_current :: proc() -> string {
	if len(tls_workspace_override) > 0 {
		return tls_workspace_override
	}
	if st := state(); st != nil && len(st.workspace) > 0 {
		return st.workspace
	}
	if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
		return v
	}
	return ""
}
