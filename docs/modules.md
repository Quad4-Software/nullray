# Modules

Modules are compiled-in extensions. Each module is a directory under
`nullray/modules/<id>/` with a `mod.odin` that registers itself at startup.
The build regenerates `cmd/nullray/modules_gen.odin` with one side-effect
import per directory, so adding a module is a folder plus `make` - no
core file edits, no registration table to patch.

## Writing a module

A module is `nullray/modules/<id>/` containing `mod.odin`, `mod.c`, or
both. `make` regenerates the import list, compiles `mod.c` to `mod.o`, and
relinks. Removing the directory uninstalls the module.

### Odin modules

`nullray/modules/hello/mod.odin`:

```odin
package hello

import "core:fmt"
import "nullray:modules"

HELLO_TOOLS: [1]modules.Tool_Spec = {{
	name = "hello_tool",
	description = "Say hello",
	schema_json = `{"type":"object","properties":{},"required":[]}`,
	kind = .Read,
	run = hello_run,
}}

HELLO_COMMANDS: [1]modules.Command_Spec = {{
	name = "hello",
	help = "greet",
	prompt = "Call hello_tool and answer plainly.",
}}

@(init)
hello_init :: proc "contextless" () {
	context = runtime.default_context()
	modules.modules_register(modules.Module{
		id = "hello",
		name = "Hello",
		version = "0.1.0",
		description = "example",
		tools = HELLO_TOOLS[:],
		commands = HELLO_COMMANDS[:],
	})
}

hello_run :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return fmt.aprintf("hello from a module", allocator = allocator), ""
}
```

Then `make`. `nullray --list-modules` shows it loaded.

### C modules

C modules currently build on Linux and macOS only. The generated import
glue is POSIX-gated so Windows builds skip them cleanly.

`nullray/modules/mymod/mod.c`:

```c
#include "../nullray_module.h"
#include <stdlib.h>
#include <string.h>

static char *my_tool_run(const char *args_json, char **err_out)
{
	(void)args_json, (void)err_out, return strdup("ok");
}

NULLRAY_MODULE_ENTRY(mymod)
{
	nullray_module_begin("mymod", "My Module", "0.1.0", "example"), nullray_module_add_tool("my_tool", "Do a thing",
		"{\"type\":\"object\",\"properties\":{},\"required\":[]}",
		NULLRAY_TOOL_READ, my_tool_run), nullray_module_end();
}
```

Contract:

- The directory name is the C identifier: `nullray_<id>_module_init` is
  the entry point, made by `NULLRAY_MODULE_ENTRY(<id>)`. Ids are
  `[a-z0-9_]` only.
- Run procs get `args_json` as a borrowed cstring, valid for the call.
- Return a `malloc`'d result string or NULL. Write a `malloc`'d error
  through `err_out` on failure. Nullray copies both then `free()`s them.
- `NULLRAY_TOOL_READ` / `WRITE` / `SHELL` map to the same permission
  gates as Odin modules.
- Commands use `nullray_module_add_command(name, help, prompt)`.
- The C API is `nullray/modules/nullray_module.h` - include it as
  `../nullray_module.h` from a module dir.

## What a module can contribute

- `tools` - named tool calls with a JSON schema, a `kind` (Read, Write,
  Shell) that gates sandbox/permission behavior, and a `run` proc taking
  the args JSON and returning `(result, err)`.
- `commands` - prompt-template slash commands. `prompt` expands
  `$ARGUMENTS` and `$1`..`$9` like `.nullray/commands/*.md` files.

Modules are code in the build: they get everything core code gets, with no
sandbox exemption beyond what their tool `kind` implies. Write tools that
take untrusted model input in `args_json` - parse it, validate it, and
never shell-interpolate it.

## Gating

`NULLRAY_MODULES=off` loads nothing. `NULLRAY_MODULES=alpha,beta` loads a
CSV allowlist. `NULLRAY_MODULES=all` (or unset) loads everything.

## Notes for module authors

- Registration runs inside `@(init)` procs, which are `contextless`:
  set `context = runtime.default_context()` first. Keep spec data in
  package-level variables, not slice literals inside the init proc -
  literal storage in init context is not stable and registers garbage.
  After that the init proc should only register. do real work inside `run`.
- Keep module packages import-light. `nullray:modules` is a leaf by
  design. importing heavy packages from `mod.odin` drags them into every
  build and slows init.
- Struct fields are read straight into the registry: clone anything
  mutable, but string literals and static arrays are fine.
- `scripts/gen_modules.odin` only scans for `mod.odin` files. helper files
  in the same directory are regular package code.
