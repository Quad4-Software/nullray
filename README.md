# nullray

Lightweight coding agent with a custom TUI built with Odin.

![nullray](logo/nullray-social.png)

## Features

- Simple, Lightweight, Fast with a small memory footprint
- Landlock/seccomp sandbox on Linux (soft skip on other OS)
- Custom TUI
- Privacy-focused
- MCP and Skills support
- Headless and CI friendly
- Docker (GHCR), Flatpak, and AppImage
- Customizable
- Neovim and Emacs keybindings options

Supported providers: OpenAI, OpenAI-compatible, Anthropic, Gemini, Groq, DeepSeek, Mistral, Together, Fireworks, xAI, Azure OpenAI, OpenRouter, LM Studio, Ollama, OpenCode

Supported platforms: Linux, macOS, Windows

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

Needs Odin and libcurl. On Linux, Landlock is used when the kernel supports it. CI is in `.github/workflows/` (`ci.yml` plus cross-platform `print.yml`).

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
--sandbox --workspace --session --list-sessions --ephemeral
--list-models --keys --no-splash
```

Session management:

```text
nullray --session NAME
nullray --list-sessions
nullray --search-sessions QUERY
nullray --delete-session NAME
nullray --export-session NAME --out DIR
nullray --import-session PATH [--as NAME]
```

On TUI quit, nullray prints `To resume this session: nullray --session <name>` when the session was persisted.

## Docker

Images publish to GHCR on master and on `v*.*.*` tags (linux/amd64 + linux/arm64). Base is digest-pinned Debian trixie-slim, multi-stage, rootless uid 1000.

```sh
docker pull ghcr.io/quad4-software/nullray:latest

docker run --rm -it \
  -e TERM -e COLORTERM \
  -e NULLRAY_PROVIDER=ollama \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD:/workspace" \
  -v nullray-config:/home/nullray/.config/nullray \
  -w /workspace \
  ghcr.io/quad4-software/nullray:latest
```

Compose (stdin/tty attached as a terminal):

```sh
docker compose run --rm nullray
```

Local image without registry:

```sh
make docker-build
docker run --rm -it -e TERM -v "$PWD:/workspace" -w /workspace nullray:local
```

## Flatpak and AppImage

Release tags ship `*.flatpak` (Freedesktop 25.08) and AppImage (FUSE3 runtime).

```sh
# Flatpak bundle from a release
flatpak install --user ./nullray_*_linux_amd64.flatpak
flatpak run io.github.Quad4_Software.nullray

# AppImage
chmod +x ./nullray_*_linux_amd64.AppImage
./nullray_*_linux_amd64.AppImage
```

From a local build (needs packaging tools on the host):

```sh
make appimage
make flatpak
```

## Agent

Multi-step tool loop with OpenAI-style tool_calls and TOOL text fallback.

Tools: read, write, edit, apply_edits, grep, glob, shell, run_script.

Loads AGENTS.md and skills (cap 48, 24KB each).

Sessions live under ~/.config/nullray/sessions/ as JSONL plus .meta.json.

```text
--session NAME
--ephemeral
NULLRAY_EPHEMERAL=1
/ephemeral on
/sessions /search /resume /new /fork /delete
```

`--session NAME` resumes or creates a named session (same paths as `/resume`). Pass a `.jsonl` path or a path with `/` to use a raw file. Quit prints a resume command when the session was saved.

Per-session .lock files keep two live instances off the same transcript. Concurrent processes use runtime/nullray-PID.lock.

## Controls

| Action | How |
|--------|-----|
| Mode ask/plan/review/edit | /mode or NULLRAY_MODE |
| Shell ask/allow/yolo | /perms or NULLRAY_PERMS |
| Approve shell once | /allow (after pending) |
| Deny pending shell | /deny |
| Autonomous | /auto on or NULLRAY_AUTO=1 |
| One-shot (no TUI) | `--print` / `-P` with a prompt |
| Plan .md artifact | plan mode writes `.nullray/plans/` or `--plan-out` |
| Stop / pause / continue | Esc, F3, /continue |
| Improve prompt | F2 or /improve, Ctrl-Z undo |
| Review pass | /review on or NULLRAY_REVIEW |
| Undo last write | /undo |
| Attach file | /attach path |
| Copy reply | /copy |
| Paste | Ctrl-V / Ctrl-Y / bracketed paste |
| Newline in input | Ctrl-J (Enter sends) |
| Secrets allow | /secrets path or NULLRAY_SECRETS_ALLOW |

### Print mode (CI / scripts)

```sh
nullray --print --mode ask "What does session_init do?"
nullray --print --mode plan --plan-out ./plan.md "Add ephemeral print mode"
git diff origin/main...HEAD | nullray --print --bare --mode review --fail-on-findings "Review this PR diff"
nullray --print --mode edit --perms yolo --auto "Fix the failing test"
```

Defaults under `--print`: ephemeral session, mode ask. Edit requires `--perms allow` or `yolo`. `--bare` skips home MCP and non-workspace skills. `--output-format json` emits a single JSON object. Exit `1` with `--fail-on-findings` when a review ends with `FINDINGS: N` and N > 0. Provider errors exit `2`.

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

OpenRouter retries HTTP 429/502/503 with backoff and `provider.allow_fallbacks`. Failed upstream provider names are added to `provider.ignore` on retry. Optional: `NULLRAY_HTTP_RETRIES` (default 3), `NULLRAY_FALLBACK_MODELS=model-a,model-b`, `NULLRAY_OPENROUTER_IGNORE=DeepInfra,Fireworks`.

Limited terminals (`TERM=dumb`, `NO_COLOR`) skip mouse and alt-screen by default. Override with `NULLRAY_MOUSE` / `NULLRAY_ALT_SCREEN`. WSL and plain TTYs fall back to `COLUMNS`/`LINES` when ioctl size is missing. Color defaults to 256-color unless `COLORTERM=truecolor` or `NULLRAY_COLOR` is set.

## Providers

| Provider | Notes |
|----------|-------|
| openai | Official API. OPENAI_API_KEY |
| openai-compat | Any Chat Completions base URL |
| anthropic | OpenAI-compat layer. ANTHROPIC_API_KEY |
| gemini | Google OpenAI-compat. GEMINI_API_KEY or GOOGLE_API_KEY |
| groq | GROQ_API_KEY |
| deepseek | DEEPSEEK_API_KEY |
| mistral | MISTRAL_API_KEY |
| together | TOGETHER_API_KEY |
| fireworks | FIREWORKS_API_KEY |
| xai | XAI_API_KEY |
| azure | AZURE_OPENAI_ENDPOINT + AZURE_OPENAI_API_KEY (api-key header) |
| ollama | Local. OLLAMA_HOST |
| lmstudio | Local. LM_API_TOKEN defaults to lm-studio |
| openrouter | OPENROUTER_API_KEY |
| opencode / opencode-go | OpenCode Zen endpoints |

Official OpenAI:

```ini
NULLRAY_PROVIDER=openai
OPENAI_API_KEY=sk-...
NULLRAY_MODEL=gpt-5.4-mini
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

Assets live in logo/. Regenerate the splash GIF with `python3 scripts/gen_splash_gif.py`.

## License

0BSD [LICENSE](LICENSE)
