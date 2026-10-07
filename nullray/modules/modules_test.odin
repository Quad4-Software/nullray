package modules

import "core:os"
import "core:testing"
import "core:strings"

@(test)
test_register_and_list :: proc(t: ^testing.T) {
	modules_register(Module{
		id = "unittest",
		name = "Unit Test",
		version = "0.0.1",
		tools = []Tool_Spec{{name = "ut_tool", kind = .Read}},
		commands = []Command_Spec{{name = "utcmd", help = "h", prompt = "p"}},
	})
	found := false
	for m in modules_list() {
		if m.id == "unittest" {
			found = true
			testing.expect_value(t, len(m.tools), 1)
			testing.expect_value(t, len(m.commands), 1)
			testing.expect_value(t, m.tools[0].name, "ut_tool")
		}
	}
	testing.expect(t, found)
}

@(test)
test_module_enabled_gates :: proc(t: ^testing.T) {
	testing.expect(t, module_enabled("anything"))
	os.set_env("NULLRAY_MODULES", "off")
	defer os.unset_env("NULLRAY_MODULES")
	testing.expect(t, !module_enabled("anything"))
	os.set_env("NULLRAY_MODULES", "alpha,beta")
	testing.expect(t, module_enabled("beta"))
	testing.expect(t, !module_enabled("gamma"))
}

@(test)
test_tool_run_proc_type :: proc(t: ^testing.T) {
	spec := Tool_Spec{name = "x", run = proc(args_json: string, allocator := context.allocator) -> (string, string) {
		return strings.clone("ok", allocator), ""
	}}
	out, err := spec.run("{}", context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, out, "ok")
}
