---
name: memory
description: >
  Allocation ownership and destroy rules for nullray providers, sessions,
  and tests. Use when adding owned strings, dynamics, or teardown paths.
---

# Memory management

## Who owns what

The creator of a heap string or `[dynamic]T` owns it until a documented handoff. Store clones on long-lived structs. Do not keep pointers into `context.temp_allocator` data across frame, job, or HTTP boundaries.

| Area | Own | Tear down |
|------|-----|-----------|
| Provider | `base_url`, `api_key`, `default_model` | `provider_destroy` |
| Registry | `[dynamic]Provider` | `registry_destroy` (destroys each provider) |
| Session messages | role content, tool call fields | `destroy_message` / `session_destroy` |
| Session pending events | `text`, `name`, `reasoning` | delete each then `delete(pending)` |
| Sandbox config/state | path strings and allow lists | `config_destroy`, `state_destroy` |
| Skills / tools / MCP | loaded tables | `skills_destroy`, `tools_destroy`, `mcp_destroy` |

When replacing a field (`p.default_model = strings.clone(model)`), `delete` the old value first. See `registry_select_from_env`.

## Temp vs permanent

Use `context.temp_allocator` for:

- `os.lookup_env` scratch
- path joins and cleans used only in the current proc
- JSON parse trees consumed before return
- builders that feed a final `strings.clone` into the caller allocator

Use the default allocator (or an explicit permanent one) for anything stored on App, Session, Provider, or Tool registries.

## Destroy procs

Pair every `_init` / `make_*` with a destroy. Call destroys from the owner (`app_destroy` already chains registry and session). Job and improve paths that clone a Provider must call `provider_destroy` on that copy.

Avoid double free: destroy nested owned strings once. `test_destroy_messages_no_double_free` in `provider/usage_test.odin` is the pattern for message teardown.

## Tests

Prefer a tracking allocator around unit tests that allocate so leaks fail the test. Defer destroy of every buffer, provider, and dynamic you create in the test body. Keep `ODIN_TEST_THREADS=1` when tests share globals (tools, MCP, sandbox state).
