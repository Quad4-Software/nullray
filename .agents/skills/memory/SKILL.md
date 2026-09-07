---
name: memory
description: >
  Allocation ownership and destroy rules for nullray providers, sessions,
  and tests. Use when adding owned strings, dynamics, or teardown paths.
---

# Memory

Creator of a heap string or [dynamic]T owns it until a documented handoff. Clone onto long-lived structs. Never keep temp_allocator pointers across frame, job, or HTTP boundaries.

## Own / tear down

| Area | Own | Tear down |
|------|-----|-----------|
| Provider | base_url, api_key, default_model | provider_destroy |
| Registry | [dynamic]Provider | registry_destroy |
| Session messages | role content, tool call fields | destroy_message / session_destroy |
| Pending events | text, name, reasoning | delete each then delete(pending) |
| Sandbox | path strings, allow lists | config_destroy, state_destroy |
| Skills / tools / MCP | loaded tables | skills_destroy, tools_destroy, mcp_destroy |

Replace a field with delete(old) then strings.clone(new). See registry_select_from_env.

## Temp vs permanent

Temp: os.lookup_env scratch, path joins used only in-proc, JSON trees consumed before return, builders that feed a final clone.

Permanent (default allocator): App, Session, Provider, tool registries.

## Destroy pairs

Pair every _init / make_* with destroy. app_destroy chains registry and session. Job and improve paths that clone a Provider must provider_destroy that copy.

Destroy nested owned strings once. Pattern: test_destroy_messages_no_double_free in provider/usage_test.odin.

## Tests

Tracking allocator so leaks fail. Defer destroy of every buffer, provider, and dynamic you create. Keep ODIN_TEST_THREADS=1 when tests share globals.

Cross-ref: `.agents/references/footguns.md`.
