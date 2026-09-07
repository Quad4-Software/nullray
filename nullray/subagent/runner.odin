// SPDX-License-Identifier: 0BSD
/*
Registered turn runner so subagent can spawn without importing agent/tools.
*/

package subagent

import "nullray:provider"

Child_Turn_Result :: struct {
	ok:          bool,
	content:     string,
	err:         string,
	stopped:     string,
	usage:       provider.Usage,
}

/*
tools_reg is an opaque tools.Registry pointer owned by the app.
stop_user is passed to the stop check (Child_Job pointer).
*/
Run_Child_Turn_Proc :: #type proc(
	prov: ^provider.Provider,
	messages: []provider.Message,
	model: string,
	mode: string,
	max_steps: int,
	tools_reg: rawptr,
	stop_user: rawptr,
	allocator := context.allocator,
) -> Child_Turn_Result

Stop_Check_Cancel_Proc :: #type proc(user: rawptr) -> bool

g_run_child_turn: Run_Child_Turn_Proc

register_run_child_turn :: proc(p: Run_Child_Turn_Proc) {
	g_run_child_turn = p
}
