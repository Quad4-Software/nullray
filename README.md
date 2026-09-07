# nullray

Odin coding agent with a custom TUI, Landlock/seccomp sandbox, and a native tool loop. No Node.

**Version:** 0.1.0

## Build / install

```sh
git clone git@github.com:Quad4-Software/nullray.git
cd nullray
make
make test
make install   # PREFIX=/usr/local by default
```

After `make install`, run `nullray` from your PATH. From a local build without install, use `./bin/nullray`.

```sh
nullray --self-test
nullray
```

Needs Odin, libcurl, and Linux Landlock. CI runs on push via `.github/workflows/ci.yml`.

Shell completions and man page:

```sh
nullray --completions zsh > ~/.zsh/completions/_nullray
nullray --man | man -l -
make install   # also installs man/nullray.1 and share/nullray/completions/
```

Useful flags: `--provider`, `--model`, `--theme`, `--mode`, `--perms`, `--sandbox`, `--workspace`, `--session`, `--list-models`, `--ephemeral`.

## Agent

Multi-step tool loop with OpenAI-style tool_calls and TOOL text fallback. Tools: read, write, edit, apply_edits, grep, glob, shell, run_script. Loads AGENTS.md and skills (cap 48, 24KB each).

Sessions: JSONL under `~/.config/nullray/sessions/` plus `.meta.json`. Ephemeral via `--ephemeral`, `NULLRAY_EPHEMERAL=1`, or `/ephemeral on`. Per-session `.lock` files prevent two live nullrays from sharing one transcript. Multiple nullray processes can run different sessions concurrently (`runtime/nullray-<pid>.lock`).

## Controls

| Action | How |
|--------|-----|
| Mode ask/plan/edit | `/mode`, `NULLRAY_MODE` |
| Shell ask/allow/yolo | `/perms`, `NULLRAY_PERMS` |
| Approve shell once | `/allow` (after pending) |
| Deny pending shell | `/deny` |
| Autonomous | `/auto on`, `NULLRAY_AUTO=1` |
| Stop / pause / continue | Esc, F3, `/continue` |
| Improve prompt | F2 / `/improve`, Ctrl-Z undo |
| Review pass | `/review on`, `NULLRAY_REVIEW` |
| Undo last write | `/undo` |
| Attach file | `/attach path` |
| Copy reply | `/copy` |
| Paste | Ctrl-V / Ctrl-Y / bracketed paste |
| Newline in input | Ctrl-J (Enter sends) |
| Secrets allow | `/secrets path`, `NULLRAY_SECRETS_ALLOW` |

## Config (`~/.config/nullray/env`)

```
NULLRAY_PROVIDER=openrouter
NULLRAY_MODEL=google/gemini-3.8-flash
NULLRAY_REASONING=low
NULLRAY_MODE=edit
NULLRAY_PERMS=allow
NULLRAY_IMPROVE_MODEL=
NULLRAY_REVIEW_MODEL=
NULLRAY_CACHE=1
OPENROUTER_API_KEY=sk-or-...
```

Secrets (`.env*`, keys, `.ssh/`, …) are blocked for tools and shell unless listed in `NULLRAY_SECRETS_ALLOW`. Privacy scrub + path redaction remain on by default.

Prompt cache: system `cache_control` + `prompt_cache_key` for OpenRouter (`NULLRAY_CACHE=0` disables). Native tool_call history is kept for better cache/resume.

## Providers

Ollama, LM Studio, OpenRouter, OpenCode, OpenCode Go. MCP via `~/.config/nullray/mcp.json`.

Ollama lists models via `/v1/models` with fallback to native `/api/tags`. LM Studio uses `/v1/models` and defaults `LM_API_TOKEN` to `lm-studio` when unset. Host overrides: `OLLAMA_HOST`, `LM_STUDIO_HOST`.

## License

0BSD. See [LICENSE](LICENSE).
