# Providers

Pick a provider with `--provider`, `NULLRAY_PROVIDER`, or `/provider`
inside the TUI. `/providers` lists every built-in and whether its key is
present.

Built-in cloud vendors outside this table are not registered. Use
`openai-compat` with any chat/completions base URL when you need a custom
gateway.

| Provider id | Auth env | Notes |
|-------------|----------|-------|
| ollama | none, `OLLAMA_HOST` | Local. Default host 127.0.0.1:11434 |
| lmstudio | `LM_API_TOKEN` | Local. Defaults to the value lm-studio when unset |
| llamacpp | `LLAMA_CPP_HOST`, `LLAMA_CPP_API_KEY` | Local. Probes 8080, 8081, 9931. Adopts loaded GGUF name and n_ctx from `/props` |
| openai-compat | `OPENAI_BASE_URL` + optional `OPENAI_API_KEY` | Any chat/completions endpoint |
| openrouter | `OPENROUTER_API_KEY` | Model list, fallbacks, credits |
| opencode | `OPENCODE_API_KEY` | OpenCode Zen subscription |
| opencode-go | `OPENCODE_API_KEY` | Zen Go surface |
| fireworks | `FIREWORKS_API_KEY` | |

`zen` is accepted as an alias for `opencode`. `oai`, `custom`, and
`compatible` alias to `openai-compat`.

## Keys

Keys come from three places, in order: process environment, the env
file, and foreign config adoption. nullray snapshots them before the
sandbox applies, so adopted or exported keys survive the privacy scrub
that empties sensitive variables for tool processes.

### Foreign adoption

If a supported AI CLI already has credentials, nullray imports them on
startup. It reads the config files directly, never executes helper
commands like `apiKeyHelper`, and fills only variables that are unset.
Provider votes need a usable credential, and a custom provider base URL
routes through `openai-compat` rather than sending a proxy key to an
unsupported vendor host. `NULLRAY_ADOPT=0` disables it. `--doctor` lists
every detected source without printing values.

Two limits worth knowing: OAuth access tokens that need a Bearer
exchange are skipped (most third-party OpenCode oauth entries), and
OpenCode v2 stores credentials in a SQLite database that nullray does
not read.

## Models

`--model NAME`, `NULLRAY_MODEL`, or `/model` picks the model.
`/models` shows the live catalog for the active provider with context
sizes and pricing when the models.dev cache is warm, plus which API
surface an OpenCode Zen model needs (chat, messages, responses,
gemini, or systemone). `NULLRAY_MODELSDEV=0` disables that cache.

Reasoning effort: `NULLRAY_REASONING` or `/reasoning` (low, medium,
high, none). pi thinking-level defaults adopt into this.

`/model lock` freezes the current model so agent-driven switches and
subagent role maps cannot change it.

## Failover

- `NULLRAY_PROVIDER_FALLBACKS=ollama,openrouter,fireworks` retries other
  providers on chat auth and payment failures.
- `NULLRAY_FALLBACK_MODELS` lists models to try on OpenRouter routing
  failures.
- `NULLRAY_HTTP_RETRIES` controls 429/502/503 retries.
- `NULLRAY_OPENROUTER_ZDR` requests zero data retention routes.
- `OPENROUTER_CREDITS_KEY` enables `/credits` account balance.

## Embeddings

RAG and search use an embedder picked by `NULLRAY_EMBED_PROVIDER` and
`NULLRAY_EMBED_MODEL`. Ollama gets a native `/api/embed` path and other
providers use the OpenAI embeddings shape. Prefer a local embedder when
the chat model is local so nothing leaves the machine.

## Local endpoints

```ini
NULLRAY_PROVIDER=openai-compat
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=optional
NULLRAY_MODEL=my-local-model
```

`NULLRAY_LOCAL_PROBE` controls whether the setup wizard probes localhost
servers. `NULLRAY_QUIRKS` and `/quirks` show model output workarounds
the session is applying.

On local providers (and model ids that contain gguf) a tool-call turn
clamps temperature to 0.2 and sends `repeat_penalty` 1.0.
`NULLRAY_GGUF_SAMPLE=0` turns that off.
