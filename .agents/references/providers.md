# Provider reference

Ids are NULLRAY_PROVIDER values. Bases are OpenAI Chat Completions style unless noted. Keys come from env (and ~/.config/nullray/env). Shared fallback: NULLRAY_API_KEY. Override base with NULLRAY_BASE_URL where supported.

| Id | Env key(s) | Default base |
|----|------------|--------------|
| anthropic | ANTHROPIC_API_KEY | https://api.anthropic.com/v1 |
| gemini | GEMINI_API_KEY, alt GOOGLE_API_KEY | https://generativelanguage.googleapis.com/v1beta/openai |
| groq | GROQ_API_KEY | https://api.groq.com/openai/v1 |
| deepseek | DEEPSEEK_API_KEY | https://api.deepseek.com/v1 |
| mistral | MISTRAL_API_KEY | https://api.mistral.ai/v1 |
| together | TOGETHER_API_KEY | https://api.together.xyz/v1 |
| fireworks | FIREWORKS_API_KEY | https://api.fireworks.ai/inference/v1 |
| xai | XAI_API_KEY | https://api.x.ai/v1 |
| azure | AZURE_OPENAI_API_KEY, alt OPENAI_API_KEY. Endpoint: AZURE_OPENAI_ENDPOINT | (empty until endpoint set) |
| cerebras | CEREBRAS_API_KEY | https://api.cerebras.ai/v1 |
| cohere | COHERE_API_KEY, alt CO_API_KEY | https://api.cohere.ai/compatibility/v1 |
| nvidia | NVIDIA_API_KEY | https://integrate.api.nvidia.com/v1 |
| dashscope | DASHSCOPE_API_KEY | https://dashscope.aliyuncs.com/compatible-mode/v1 |
| openai | OPENAI_API_KEY. Base override: OPENAI_BASE_URL | https://api.openai.com/v1 |
| openai-compat | OPENAI_API_KEY / NULLRAY_API_KEY. Base: OPENAI_BASE_URL or NULLRAY_BASE_URL | (required) |
| ollama | OLLAMA_HOST | http://127.0.0.1:11434/v1 |
| lmstudio | LM_API_TOKEN (default lm-studio), host LM_STUDIO_HOST | http://127.0.0.1:1234/v1 |
| llamacpp | optional LLAMA_CPP_API_KEY, host LLAMA_CPP_HOST | http://127.0.0.1:8080/v1 |
| openrouter | OPENROUTER_API_KEY | https://openrouter.ai/api/v1 |
| opencode | OPENCODE_API_KEY | https://opencode.ai/zen/v1 |
| opencode-go | OPENCODE_API_KEY | https://opencode.ai/zen/go/v1 |

OpenCode notes:

- Chat, stream, and models requests send `x-opencode-session` with the live session name (process fallback when unset). Required for Go routing and cache affinity.
- HTTP User-Agent is `nullray/<VERSION>`.

OpenRouter notes:

- Chat requests send `provider.allow_fallbacks: true`.
- On 429/502/503 nullray retries (NULLRAY_HTTP_RETRIES, default 3) and ignores failed upstream providers from the error metadata.
- NULLRAY_FALLBACK_MODELS=a,b adds OpenRouter `models` fallbacks.
- NULLRAY_OPENROUTER_IGNORE=DeepInfra,Fireworks pre-ignores providers.
- Friendlier 429 text points at BYOK integrations when the shared pool is saturated.
- NULLRAY_OPENROUTER_ZDR=off|warn|require (default warn when the active provider is openrouter). require adds `provider.zdr: true` and, by default, `provider.data_collection: deny`. warn prints a one-time stderr note that ZDR is not enforced. off disables both injection and the note. ZDR fields are omitted when failover switches to a non-openrouter provider.
- NULLRAY_OPENROUTER_DATA_COLLECTION=deny|allow overrides the default deny pairing in require mode (default deny when unset).
- OpenRouter plugin/tool endpoints may not honor the same provider routing object as chat completions. Treat ZDR as a routing hint for the chat API, not a guarantee for every OpenRouter surface.

Aliases in normalize_provider_id:

```
claude -> anthropic
google / google-gemini -> gemini
grok -> xai
oai -> openai
openai_compatible / compatible / custom -> openai-compat
azure-openai -> azure
qwen / alibaba -> dashscope
nim / nvidia-nim -> nvidia
co -> cohere
llama.cpp / llama-cpp / llama -> llamacpp
lm-studio -> lmstudio
```

Local notes:

- NULLRAY_LOCAL_PROBE=0|false|off|no skips HTTP live/down probes and auto-select.
- With no NULLRAY_PROVIDER / -p, registry auto-selects the first live local among ollama, lmstudio, llamacpp.
- Embeddings: POST {base}/embeddings (encoding_format float). Ollama falls back to native POST /api/embed on 404.
- NULLRAY_EMBED_PROVIDER / NULLRAY_EMBED_MODEL override the chat provider for vectors. Defaults: ollama nomic-embed-text, openrouter openai/text-embedding-3-small, openai text-embedding-3-small. lmstudio and llamacpp require NULLRAY_EMBED_MODEL.
- NULLRAY_RAG=auto|1|0 (default auto). Index under .nullray/rag/. NULLRAY_RAG_ARTIFACTS=0 skips artifact indexing.

Source of truth: nullray/constants/constants.odin and nullray/provider/builtins.odin.
