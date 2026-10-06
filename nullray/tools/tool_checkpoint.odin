// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Model-facing checkpoint tools over the snapshot store.
*/

package tools

tool_checkpoint_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	return checkpoint_list(allocator), ""
}

tool_checkpoint_restore :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, ierr := json_arg_int_optional(args_json, "id", 0, allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	msg, ok := checkpoint_restore(id, allocator)
	if !ok {
		return "", msg
	}
	return msg, ""
}

tool_checkpoint_diff :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, ierr := json_arg_int_optional(args_json, "id", 0, allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	msg, ok := checkpoint_diff(id, allocator)
	if !ok {
		return "", msg
	}
	return msg, ""
}

register_checkpoint_tools :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	registry_register(r, Tool{
		name = "checkpoint_list",
		description = "List workspace checkpoints (step label, files, approx size) taken before agent writes",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_checkpoint_list,
	})
	registry_register(r, Tool{
		name = "checkpoint_diff",
		description = "Show what changed in the workspace since a checkpoint id from checkpoint_list",
		schema_json = `{"type":"object","properties":{"id":{"type":"string","description":"checkpoint id"}},"required":["id"]}`,
		kind = .Read,
		run = tool_checkpoint_diff,
	})
	registry_register(r, Tool{
		name = "checkpoint_restore",
		description = "Restore the exact file set recorded at a checkpoint id from checkpoint_list (created files are removed, edited files revert)",
		schema_json = `{"type":"object","properties":{"id":{"type":"string","description":"checkpoint id"}},"required":["id"]}`,
		kind = .Write,
		run = tool_checkpoint_restore,
	})
}

