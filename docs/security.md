# Security

## What leaves the machine

Everything a model sees goes to the provider: prompts, tool results,
file excerpts, system prompt. nullray treats provider API keys and
secrets differently from that stream.

- Known secret paths are denylisted before tools can read them, and
  secret-looking strings get redacted from tool output.
- Provider keys are cached before the sandbox scrubs them from the
  process environment, so a `run_shell` child never sees
  `OPENAI_API_KEY` even though the provider still works.
- Passwords on the elevate path go through askpass and never reach a
  tool result or a provider message.
- `NULLRAY_SECRETS_ALLOW` or `/secrets PATH` is the explicit escape
  hatch for paths the agent legitimately needs, like a kubeconfig.
- `--hide-sensitive` or `NULLRAY_HIDE_SENSITIVE` blanks balances and
  credit labels in the UI.

## Foreign config adoption

Adoption reads third-party AI CLI configs but is deliberately
conservative:

- Only unset variables get filled. Your env, CLI flags, and env file
  always win.
- Helper commands (`apiKeyHelper`, `!cmd` indirections) are never
  executed. `{env:X}` and `{file:...}` references resolve.
- OAuth tokens that would need a Bearer exchange are noted in `--doctor`
  but not imported.
- A foreign proxy base URL routes through `openai-compat` instead of
  pointing a vendor provider at a host it does not expect, so a relay
  key never ships to the real vendor.
- Values stay out of logs and out of `--doctor`. Only env names and
  source paths print.
- `NULLRAY_ADOPT=0` disables the whole thing.

## Trust boundaries

- **Workspace hooks**: `.nullray/hooks.json` runs shell commands on
  tool events. Unknown or changed hooks need `/hooks trust` first.
- **MCP servers**: entries in `mcp.json` autoload on startup unless
  trust rules say otherwise. `NULLRAY_MCP_ALLOW_ANY` skips the prompt,
  `NULLRAY_MCP_APPROVE_DRIFT` re-approves changed tool lists.
- **Subagents**: explore children share the workspace with path leases.
  Edit children get isolated worktrees under `.nullray/worktrees/` and
  changes apply only after `/agents apply`.
- **`--review`** reads diffs from local VCS only.

## Audit

```sh
nullray --audit
```

Scans the workspace for CI and supply-chain problems: unpinned GitHub
Actions, Dockerfile issues, compose misconfig, credential-shaped
strings, and missing lock files. Exits 1 when it finds high-severity
findings, so it gates pipelines.

## Crash dumps

Fatal signals and asserts write a dump to
`~/.config/nullray/crashes/`. `--doctor` prints the newest path. Dumps
capture state for debugging, so treat them like logs before sharing.
