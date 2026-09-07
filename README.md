# nullray

Lightweight coding agent with a custom TUI built with Odin.

![nullray](logo/nullray-social.png)

## Features

- Simple, Lightweight, Fast with a small memory footprint
- Landlock/seccomp sandbox
- Custom TUI
- Privacy-focused
- MCP and Skills support

Supported providers: OpenAI, OpenAI-compatible, OpenRouter, LM Studio, Ollama, OpenCode

Supported platforms: Linux

Windows and macOS coming soon.

## Build / install

```sh
git clone git@github.com:Quad4-Software/nullray.git
cd nullray
make
make test
make install
```

PREFIX defaults to /usr/local. After install, nullray is on your PATH.

From a tree without install:

```sh
./bin/nullray --self-test
./bin/nullray
```

Needs Odin, libcurl, and Linux Landlock. CI is in .github/workflows/ci.yml.

### Completions and man page

```sh
nullray --completions zsh > ~/.zsh/completions/_nullray
nullray --man | man -l -
make install
```

make install also installs man/nullray.1 and share/nullray/completions/.

Useful flags:

```text
--provider --model --theme --mode --perms
--sandbox --workspace --session --list-models --ephemeral
```

## Agent

Multi-step tool loop with OpenAI-style tool_calls and TOOL text fallback.

Tools: read, write, edit, apply_edits, grep, glob, shell, run_script.

Loads AGENTS.md and skills (cap 48, 24KB each).

Sessions live under ~/.config/nullray/sessions/ as JSONL plus .meta.json.

```text
--ephemeral
NULLRAY_EPHEMERAL=1
/ephemeral on
```

Per-session .lock files keep two live instances off the same transcript. Concurrent processes use runtime/nullray-PID.lock.

## Controls

| Action | How |
|--------|-----|
| Mode ask/plan/edit | /mode or NULLRAY_MODE |
| Shell ask/allow/yolo | /perms or NULLRAY_PERMS |
| Approve shell once | /allow (after pending) |
| Deny pending shell | /deny |
| Autonomous | /auto on or NULLRAY_AUTO=1 |
| Stop / pause / continue | Esc, F3, /continue |
| Improve prompt | F2 or /improve, Ctrl-Z undo |
| Review pass | /review on or NULLRAY_REVIEW |
| Undo last write | /undo |
| Attach file | /attach path |
| Copy reply | /copy |
| Paste | Ctrl-V / Ctrl-Y / bracketed paste |
| Newline in input | Ctrl-J (Enter sends) |
| Secrets allow | /secrets path or NULLRAY_SECRETS_ALLOW |

## Config

File: ~/.config/nullray/env

```ini
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

Secrets (.env files, keys, .ssh, and similar) stay blocked for tools and shell unless listed in NULLRAY_SECRETS_ALLOW. Privacy scrub and path redaction stay on by default.

Prompt cache for OpenRouter uses system cache_control plus prompt_cache_key. Set NULLRAY_CACHE=0 to disable. Native tool_call history is kept for better cache and resume.

## Providers

| Provider | Notes |
|----------|-------|
| openai | Official API. OPENAI_API_KEY |
| openai-compat | Any Chat Completions base URL |
| ollama | Local. OLLAMA_HOST |
| lmstudio | Local. LM_API_TOKEN defaults to lm-studio |
| openrouter | OPENROUTER_API_KEY |
| opencode / opencode-go | OpenCode Zen endpoints |

Official OpenAI:

```ini
NULLRAY_PROVIDER=openai
OPENAI_API_KEY=sk-...
NULLRAY_MODEL=gpt-4o-mini
```

Any compatible endpoint:

```ini
NULLRAY_PROVIDER=openai-compat
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=optional
NULLRAY_MODEL=my-local-model
```

Ollama lists models via /v1/models with fallback to /api/tags. MCP config is ~/.config/nullray/mcp.json. Handshake versions span 2024-10-07 through 2025-11-25.

## Branding

Assets live in logo/. Regenerate with:

```sh
python3 scripts/gen_logo.py
```

## License

0BSD. See LICENSE.
