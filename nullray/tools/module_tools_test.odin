package tools

import "core:strings"
import "core:testing"
import "nullray:modules"

foreign import test_libc "system:c"
foreign import test_hello_c "../modules/hello_c/mod.o"
foreign test_hello_c {
	nullray_hello_c_module_init :: proc "c" () ---
}
foreign test_libc {
	malloc :: proc "c" (size: int) -> rawptr ---
}

@(private)
fake_c_run :: proc "c" (args_json: cstring, err_out: ^cstring) -> cstring {
	// echo the args back, allocated with malloc so the trampoline's free is real
	n := len(string(args_json)) + 4
	raw := cast([^]u8)malloc(n)
	s := string(args_json)
	for i in 0 ..< len(s) {
		raw[i] = s[i]
	}
	raw[len(s)] = 'O'
	raw[len(s)+1] = 'K'
	raw[len(s)+2] = '!'
	raw[len(s)+3] = 0
	return cast(cstring)raw
}

@(private)
fake_c_fail :: proc "c" (args_json: cstring, err_out: ^cstring) -> cstring {
	raw := cast([^]u8)malloc(9)
	src := "it broke"
	for i in 0 ..< 8 {
		raw[i] = src[i]
	}
	raw[8] = 0
	err_out^ = cast(cstring)raw
	return nil
}

@(test)
test_module_c_tool_trampoline :: proc(t: ^testing.T) {
	modules.modules_reset()
	defer modules.modules_reset()
	modules.modules_register(modules.Module{
		id = "c_unittest",
		tools = []modules.Tool_Spec{{
			name = "c_echo",
			description = "echo via C",
			schema_json = `{}`,
			kind = .Read,
			run_c = fake_c_run,
		}, {
			name = "c_fail",
			description = "errors via C",
			schema_json = `{}`,
			kind = .Read,
			run_c = fake_c_fail,
		}},
	})

	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)

	tool, found := registry_find(&r, "c_echo")
	testing.expect(t, found)
	testing.expect_value(t, tool.kind, Tool_Kind.Read)
	testing.expect(t, tool.run_named != nil)
	res, err := tool.run_named(tool.user, "c_echo", "abc", context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, res, "abcOK!")

	fail, found2 := registry_find(&r, "c_fail")
	testing.expect(t, found2)
	fres, ferr := fail.run_named(fail.user, "c_fail", "", context.temp_allocator)
	testing.expect_value(t, fres, "")
	testing.expect_value(t, ferr, "it broke")
}

@(test)
test_c_module_binary_link :: proc(t: ^testing.T) {
	// Calls the real compiled C module entry and runs its tool through the
	// same registry path a model call would take.
	modules.modules_reset()
	defer modules.modules_reset()
	nullray_hello_c_module_init()
	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)
	tool, found := registry_find(&r, "hello_c")
	testing.expect(t, found)
	res, err := tool.run_named(tool.user, "hello_c", "{}", context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, res, "hello from a C module")
}
