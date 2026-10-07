# Modules

Modules are compiled-in extensions. Each module is a directory under
`nullray/modules/<id>/` with a `mod.odin` that registers itself at startup.
The build regenerates `cmd/nullray/modules_gen.odin` with one side-effect
import per directory, so adding a module is a folder plus `make` - no
core file edits, no registration table to patch.

## Writing a module

`nullray/modules/hello/mod.odin`:

```odin
package hello

import "core:fmt"
import "nullray:modules"

@(init)
hello_init :: proc "contextless" () {
	context = runtime.default_context()
	modules.modules_register(modules.Module{
		id = "hello",
		name = "Hello",
		version = "0.1.0",
		description = "example",
		tools = []modules.Tool_Spec{{
			name = "hello_tool",
			description = "Say hello",
			schema_json = `{"type":"object","properties":{},"required":[]}`,
			kind = .Read,
			run = hello_run,
		}},
		commands = []modules.Command_Spec{{
			name = "hello",
			help = "greet",
			prompt = "Call hello_tool and answer plainly.",
		}},
	})
}

hello_run :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return fmt.aprintf("hello from a module", allocator = allocator), ""
}
```

Then `make`. `nullray --list-modules` shows it loaded.

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
  set `context = runtime.default_context()` before constructing the
  Module literal - slice literals allocate from `context.allocator`.
  After that the init proc should only register; do real work inside `run`.
- Keep module packages import-light. `nullray:modules` is a leaf by
  design; importing heavy packages from `mod.odin` drags them into every
  build and slows init.
- Struct fields are read straight into the registry: clone anything
  mutable, but string literals and static arrays are fine.
- `scripts/gen_modules.odin` only scans for `mod.odin` files; helper files
  in the same directory are regular package code.
