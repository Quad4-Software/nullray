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
- `ask_secret` stores values in an in-process vault and returns only the
  name. `show_view` password fields vault under `view.<id>` and return
  `[redacted]` so values do not enter tool results or transcripts.
- Session push (user/assistant/tool) runs the same secret redaction before
  msgpack/jsonl persist: key prefixes, password= markers, and card-shaped
  digit runs become `[redacted]`.
- `NULLRAY_SECRETS_ALLOW` or `/secrets PATH` is the explicit escape
  hatch for paths the agent legitimately needs, like a kubeconfig.
- `--hide-sensitive` or `NULLRAY_HIDE_SENSITIVE` blanks balances and
  credit labels in the UI.
- Plain chat still is not a vault: unstructured addresses or free text
  PII may remain unless they match a scrub pattern. Prefer ephemeral
  sessions or `/delete` after sensitive one-offs.
- Set `NULLRAY_SESSION_KEY` or `/encrypt on PASSPHRASE` to seal
  `.msgpack` transcripts with XChaCha20-Poly1305 (PBKDF2). Without the
  key, sealed files will not load.
- `NULLRAY_VAULT_EXPORT=1` injects vault names into shell/script child
  env so agent scripts can use secrets without tool JSON.
- `/scrub all|last|matching NEEDLE` rewrites the in-memory session
  (and disk if persisting) after a paste mistake.
- Agent vault: `ask_secret`, `/secret set|ask|list|forget|backend`, and CLI
  `--secret NAME=VALUE` (also `--key` / `--token`). Agents only ever
  see names and status strings, never values. Optional
  `NULLRAY_VAULT_EXPORT=1` injects vault pairs into shell children.
- FreeDesktop keyring (default when `secret-tool` exists):
  `NULLRAY_VAULT_BACKEND=auto|keyring|memory`. Uses Secret Service
  (`service=nullray`, override with `NULLRAY_KEYRING_SERVICE`). Works with
  gnome-keyring, KWallet compat, and KeePassXC when it is the active
  Secret Service provider. No keepassxc-cli integration.

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

## Command execution

`run_shell` and `run_script` apply shell policy before execution. The policy
blocks common host, process, network, and hardware inventory commands; selected
host-information paths; cloud metadata addresses; and the endpoint indicators
reported by [Cohere on Oct. 26, 2026](https://cohere.com/blog/concerning-behaviour-popular-open-weight-ai-model).
These hard blocks apply even with `NULLRAY_PERMS=yolo` or
`NULLRAY_SHELL_NET=1`. Known network clients are detected across command
chains and require approval unless shell network access is enabled.

An optional independent reviewer can inspect the exact shell command or script
before it runs:

```sh
NULLRAY_COMMAND_VERIFY=manual
NULLRAY_COMMAND_VERIFY_MODEL=ollama/MODEL_ID
```

Replace `MODEL_ID` with a model served by the selected provider.

`manual` sends the command to the configured reviewer, then requires `/allow`
or `/deny`. The reviewer is advisory in this mode; hard blocks still apply.
`auto` requires a strict JSON `allow` verdict and blocks on denial, malformed
output, missing configuration, or provider failure. `off` is the default.
An automatic verdict is a model judgment and can be manipulated by command
text; it is not a sandbox or a replacement for the static policy.
The reviewer receives only the command and its fixed review instructions, not
the conversation transcript. Choose a reviewer provider you trust; remote
providers receive command text. `NULLRAY_COMMAND_VERIFY_MODEL` must name a
different provider/model from the active pair when both primary values are
set.

With `NULLRAY_AUDIT_LOG=1`, command-policy, verifier-verdict, and blocked-URL events append to
`~/.config/nullray/audit.jsonl` (or the active XDG config directory). Entries
include a command fingerprint, decision, and policy category; raw commands and
URLs are not written.

These command checks are policy filters, not a complete shell-language or
network sandbox. A command can invoke arbitrary code, and Linux network
namespace isolation is not currently provided. Use an isolated environment or
deny network egress at the OS/container boundary for untrusted models.

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
