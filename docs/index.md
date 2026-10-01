# nullray

Terminal coding agent written in Odin. One static binary, a custom TUI, a
Landlock/seccomp sandbox on Linux, and a native tool loop that talks to
local models or any OpenAI-compatible API.

```sh
curl -fsSL https://nullray.xyz/install | sh
nullray
```

If another AI CLI is already configured on the machine, the first run
adopts its keys and defaults so there is usually nothing to type. If not,
a setup overlay walks through provider and key entry.

## What it does

- Runs an agent loop in the terminal with file tools, shell, VCS
  operations, subagents, MCP servers, skills, and session tabs.
- Sandboxes tool execution with Landlock and seccomp on Linux, and keeps
  API keys out of tool output through privacy scrubbing.
- Works offline against Ollama, LM Studio, and llama.cpp, or against a
  dozen hosted providers.
- Reviews local Git and Fossil diffs without a forge, and hunts bugs with
  a dedicated review profile.
- Ships headless too: `--print` for pipelines, `--ask` for one-shot
  questions, `--review` for CI gates.

## These docs

| Page | Covers |
|------|--------|
| [Install](install.md) | Packages, build from source, completions |
| [Quick start](quick-start.md) | First run, setup wizard, first prompt |
| [Providers](providers.md) | Provider table, keys, adoption, models |
| [Configuration](configuration.md) | Config files and every env var |
| [Modes and permissions](modes.md) | ask/plan/review/edit, gate, perms, verify |
| [TUI](tui.md) | Interface tour, tabs, binds, themes |
| [Slash commands](commands.md) | Every / command |
| [CLI reference](cli.md) | Every flag, print mode, review bot |
| [Sessions](sessions.md) | Transcripts, search, usage, compaction |
| [Sandbox](sandbox.md) | Landlock, seccomp, ops profiles, elevate |
| [Security](security.md) | Secret handling, audit, trust decisions |
| [Skills and MCP](skills-mcp.md) | Skill roots, MCP autoload and trust |
| [Subagents](subagents.md) | task tool, roles, leases, worktrees |
| [Memory and RAG](memory-rag.md) | Project memory, recall, embeddings |
| [Troubleshooting](troubleshooting.md) | Doctor output, crashes, common fixes |

Source, issues, and releases live on
[GitHub](https://github.com/Quad4-Software/nullray). License is
QSL-1.0-0BSD: source-available, converts to 0BSD two years after each
release.
