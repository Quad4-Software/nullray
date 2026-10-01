# Troubleshooting

## Doctor

```sh
nullray --doctor
```

Prints the config path, detected keys, sandbox posture (mode, ops,
extras, Landlock ABI, seccomp support), TTY state, the foreign config
section, and the newest crash dump path. Most "why is it not working"
questions answer themselves there.

## Debug logging

```sh
nullray --debug          # or NULLRAY_DEBUG=1
```

Lifecycle logs go to stderr: provider construction, sandbox rules,
key caching, MCP connect, tool calls.

## Common problems

| Symptom | Fix |
|---------|-----|
| `sandbox requires linux` | `--sandbox warn` or `off` on macOS/Windows |
| No provider ready | `/setup` in the TUI, or export a key env |
| Setup overlay keeps opening | Key env set but empty, or provider id typo. Check `--doctor` |
| Keys adopted from the wrong tool | Export the right one explicitly, env always wins. Or `NULLRAY_ADOPT=0` |
| Colors broken or mouse missing | `NULLRAY_COLOR=256` or `none`, `NULLRAY_MOUSE=0` |
| Terminal too small to draw | WSL: set `COLUMNS`/`LINES`. Otherwise resize |
| `run_shell` cannot see a tool cache | `NULLRAY_TOOLCHAIN=1` is on by default. Off? Re-enable or add the path to `NULLRAY_SANDBOX_EXTRA_RW` |
| Docker commands denied | `NULLRAY_OPS=docker` |
| Cannot read kubeconfig | `NULLRAY_OPS=kube` plus `NULLRAY_SECRETS_ALLOW=$HOME/.kube` |
| A write tool vanished in a model reply | Check `/quirks` and whether the model dropped tool schemas. `NULLRAY_AGENT_TOOLS=0` exists for models that reject them |
| Attachment refused | File over `NULLRAY_MEDIA_MAX` (15 MB default) or media disabled |
| Lost a turn after a crash | Check `~/.config/nullray/crashes/` and resume with `--session` |

## Crash dumps

Fatal signals and asserts write a dump under
`~/.config/nullray/crashes/`. `make debug` builds with symbols for
readable backtraces. Share dumps carefully: they are debug state, not
scrubbed transcripts.

## Reset

`/reset` (then `/reset confirm`) wipes sessions and config. It is the
full slate-clearing option when state gets weird.

## Still stuck

`--self-test` isolates harness problems from provider problems by
running tools, MCP, draw, and deny paths without a network call. If
self-test passes and a provider fails, the problem is upstream of the
sandbox. Issues go to
[github.com/Quad4-Software/nullray](https://github.com/Quad4-Software/nullray/issues).
