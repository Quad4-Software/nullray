<p align="center">
  <img src="logo/nullray-pixel.svg" alt="nullray" height="40">
</p>

<p align="center">Terminal coding agent in Odin. Local models first.</p>

Custom TUI, no curses. Linux Landlock and seccomp when you want a sandbox. Git and Fossil. About 5.3 MB stripped on Linux amd64.

Local: Ollama, LM Studio, llama.cpp, any OpenAI-compatible `/v1`. Cloud: OpenCode, OpenAI, Anthropic, Gemini, Groq, DeepSeek, Mistral, Together, Fireworks, xAI, Azure OpenAI, OpenRouter.

Platforms: Linux (amd64, arm64), macOS (arm64), Windows (amd64).

A smaller harness lives at [Humanity's Last Command](https://github.com/markqvist/lc).

## Features

- Local models are first class
- Does not eat your RAM
- Coding, bug hunting, and sysadmin work
- Native OS sandbox plus privacy scrubbing for cloud keys
- Reads man pages, `--help`, and language docs

Docs: [nullray.xyz/docs](https://nullray.xyz/docs)

## Install

```sh
curl -fsSL https://nullray.xyz/install | sh
```

The script clones into `~/.local/src/nullray`, builds from source, and
installs to `~/.local`. It warns and stops if git or Odin is missing.
Needs make and a C compiler too. Re-run to pull and rebuild.

## Build

```sh
git clone git@github.com:Quad4-Software/nullray.git
cd nullray
make
make test
make install
```

`make install` uses `PREFIX` (default `/usr/local`). `make install PREFIX="$HOME/.local"` needs no sudo if `~/.local/bin` is on `PATH`.

```sh
./bin/nullray --self-test
./bin/nullray
```

First TUI launch without a ready provider opens a setup overlay. Reopen it with `/setup`. Switch mid-session with `/provider ID` or `/providers`. Keys save to `~/.config/nullray/env`. Headless `--print`, `--self-test`, and CI never open the wizard.

## Config

Local, no key:

```ini
NULLRAY_PROVIDER=ollama
NULLRAY_MODEL=qwen2.5-coder:7b
NULLRAY_MODE=edit
NULLRAY_PERMS=allow
```

OpenAI-compatible local server:

```ini
NULLRAY_PROVIDER=openai-compat
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=optional
NULLRAY_MODEL=my-local-model
```

Cloud example, `~/.config/nullray/env`:

```ini
NULLRAY_PROVIDER=openrouter
NULLRAY_MODEL=google/gemini-3.8-flash
NULLRAY_REASONING=low
NULLRAY_MODE=edit
NULLRAY_PERMS=allow
NULLRAY_CACHE=1
OPENROUTER_API_KEY=sk-or-...
```

Shell exports override the file. Secrets stay blocked unless listed in `NULLRAY_SECRETS_ALLOW`. MCP lives in `~/.config/nullray/mcp.json`. Key presets (default, neovim, emacs) are `keys.ini` or `--keys` / `NULLRAY_KEYS`.

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
| opencode / opencode-go | OPENCODE_API_KEY |

## Usage

```sh
nullray

nullray -q "What does session_init do?"

nullray --print --mode ask "What does session_init do?"

nullray --review
nullray --review --staged
nullray --review --base main --paths nullray/agent,cmd/nullray
nullray --review --include-untracked --fail-on-findings --output-format json
```

In the TUI, `/review local` (or `/review local staged`, `/review local base main`) runs the same local diff review. `/review on` still enables the end-of-turn review pass after edits.

## Ops profiles

Prefer ops profiles over `NULLRAY_SANDBOX=off`:

```sh
export NULLRAY_OPS=desktop
export NULLRAY_OPS=docker
export NULLRAY_OPS=kube
export NULLRAY_SECRETS_ALLOW="$HOME/.kube"
export NULLRAY_OPS=desktop,docker
```

`desktop` keeps Landlock while you edit `~/.config`. `docker` talks to the engine socket. `kube` needs an explicit secrets allow. Extra absolute paths: `NULLRAY_SANDBOX_EXTRA_RO` / `NULLRAY_SANDBOX_EXTRA_RW`. See `/ops` and `--doctor`.

Print with sudo: `NULLRAY_ELEVATE=ticket` after a TUI approval, or `NULLRAY_ASKPASS`. Use `--perms allow` with `--print` for edit.

## Network VCS and fetch

```sh
export NULLRAY_VCS_NETWORK=1
export NULLRAY_VCS_FORCE=1
```

`NULLRAY_VCS_NETWORK=1` enables `vcs_push` / pull / fetch / PR tools. `NULLRAY_VCS_FORCE=1` allows force-push to main/master. `fetch_url` fetches public http(s) text in edit mode (size-capped, no browser).

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

QSL-1.0-0BSD ([LICENSE](LICENSE)). Source-available, free for almost all uses except competing commercial offerings, and each version converts to 0BSD two years after release.
