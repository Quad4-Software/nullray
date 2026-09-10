# nullray

Lightweight terminal agent with a custom TUI built in Odin.

![nullray](logo/nullray-social.png)

Local: Ollama, LM Studio, llama.cpp.

Cloud: OpenCode, OpenAI, OpenAI-compatible, Anthropic, Gemini, Groq, DeepSeek, Mistral, Together, Fireworks, xAI, Azure OpenAI, OpenRouter.

Platforms: Linux (amd64, arm64/aarch64), macOS (arm64), Windows (amd64).

Check out [Humanity's Last Command](https://github.com/markqvist/lc) for a more minimal and unique terminal AI harness.

## Features

- Supports Git and Fossil
- Local models are first class
- Does not eat your RAM
- Can do coding, bug hunting and sysadmin tasks.
- Native OS sandboxing and privacy scrubbing (intended for cloud models)

Can read man pages, command --help, and language docs.

## Build

```sh
git clone git@github.com:Quad4-Software/nullray.git
cd nullray
make
make test
make install
```

`make install` uses `PREFIX` (default `/usr/local`). Use `make install PREFIX="$HOME/.local"` without sudo, and add `~/.local/bin` to `PATH`.

```sh
./bin/nullray --self-test
./bin/nullray
```

First TUI launch without a ready provider opens a setup overlay (reopen with /setup). Mid-session switch with /provider ID or /providers. Keys and base URLs stay in /setup. Saves to ~/.config/nullray/env. Headless --print, --self-test, and CI never open the wizard.

## Config

~/.config/nullray/env:

```ini
NULLRAY_PROVIDER=openrouter
NULLRAY_MODEL=google/gemini-3.8-flash
NULLRAY_REASONING=low
NULLRAY_MODE=edit
NULLRAY_PERMS=allow
NULLRAY_CACHE=1
OPENROUTER_API_KEY=sk-or-...
```

Shell exports override the file. Secrets stay blocked unless listed in NULLRAY_SECRETS_ALLOW. MCP config is ~/.config/nullray/mcp.json. Key presets (default, neovim, emacs) live in keys.ini or --keys / NULLRAY_KEYS.

OpenAI-compatible local endpoint:

```ini
NULLRAY_PROVIDER=openai-compat
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=optional
NULLRAY_MODEL=my-local-model
```

| Provider | Auth |
|----------|------|
| openai | OPENAI_API_KEY |
| openai-compat | base URL + optional key |
| anthropic | ANTHROPIC_API_KEY |
| gemini | GEMINI_API_KEY or GOOGLE_API_KEY |
| groq / deepseek / mistral / together / fireworks / xai | matching *_API_KEY |
| azure | AZURE_OPENAI_ENDPOINT + AZURE_OPENAI_API_KEY |
| ollama | OLLAMA_HOST |
| lmstudio | LM_API_TOKEN (defaults to lm-studio) |
| llamacpp | LLAMA_CPP_HOST (default http://127.0.0.1:8080/v1), optional LLAMA_CPP_API_KEY |
| openrouter | OPENROUTER_API_KEY |
| opencode / opencode-go | OpenCode Zen |

## Usage

```sh
# Interactive TUI
nullray

# Quick ask
nullray -q "What does session_init do?"

# One-shot print
nullray --print --mode ask "What does session_init do?"

# Local review bot (Git or Fossil, no GitHub required)
nullray --review
nullray --review --staged
nullray --review --base main --paths nullray/agent,cmd/nullray
nullray --review --include-untracked --fail-on-findings --output-format json
```

In the TUI, `/review local` (or `/review local staged`, `/review local base main`) runs the same local diff review. `/review on` still enables the end-of-turn review pass after edits.

## Ops and OS customize

Prefer ops profiles over `NULLRAY_SANDBOX=off`:

```sh
# Edit ~/.config (Hyprland, Omarchy-style ricing) while keeping Landlock
export NULLRAY_OPS=desktop

# Drive Docker via unix sock (often root-equivalent)
export NULLRAY_OPS=docker

# Kubernetes needs an intentional secrets allow
export NULLRAY_OPS=kube
export NULLRAY_SECRETS_ALLOW="$HOME/.kube"

# Combine
export NULLRAY_OPS=desktop,docker
```

Extra absolute paths: `NULLRAY_SANDBOX_EXTRA_RO` / `NULLRAY_SANDBOX_EXTRA_RW`. See `/ops` and `--doctor`.

Server print with sudo: `NULLRAY_ELEVATE=ticket` after a TUI approval, or `NULLRAY_ASKPASS`. Use `--perms allow` with `--print` for edit.

## Network VCS and fetch

```sh
export NULLRAY_VCS_NETWORK=1   # vcs_push / pull / fetch / PR tools
export NULLRAY_VCS_FORCE=1     # allow force-push to main/master
```

`fetch_url` fetches public http(s) text (edit mode, size-capped, no browser).

## Install script

```sh
curl -fsSL https://nullray.xyz/install | sh
```

## Packages

### Docker

```sh
docker pull ghcr.io/quad4-software/nullray:latest
docker run --rm -it \
  --user 1000:1000 \
  -v "$PWD:/workspace" \
  -v nullray-config:/home/nullray/.config/nullray \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --add-host host.docker.internal:host-gateway \
  -e NULLRAY_PROVIDER=ollama \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  ghcr.io/quad4-software/nullray:latest
```

### Flatpak

```sh
flatpak install --user ./nullray_*_linux_amd64.flatpak
flatpak run xyz.nullray.code
```

## License

0BSD [LICENSE](LICENSE)
