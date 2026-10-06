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
| llamacpp | optional LLAMA_CPP_API_KEY (post-scrub via key cache), host LLAMA_CPP_HOST | http://127.0.0.1:8080/v1 |
| openrouter | OPENROUTER_API_KEY | https://openrouter.ai/api/v1 |
| opencode | OPENCODE_API_KEY | https://opencode.ai/zen/v1 |
| opencode-go | OPENCODE_API_KEY | https://opencode.ai/zen/go/v1 |

OpenCode notes:

- Zen is multi-protocol with no v2: all model traffic stays under /zen/v1 even on OpenCode v2 installs (the v2 breaking changes are the app server API and config format, not the gateway).
- Routing source of truth is the models.dev catalog (same schema the OpenCode v2 /api/model endpoint serves): each model's provider.npm picks the surface, anthropic -> messages, openai -> responses, google -> gemini, openai-compatible/none -> chat. jev-* is always the bespoke systemone endpoint. Provider-aware prefix tables are the offline fallback. Zen and Go differ: on Go, qwen3.x is chat except qwen3.8-flash, and minimax-m3/m2.7 ride messages.
- Catalog cache: api.json (about 5MB) lands at <config>/models.dev.json with a 24h TTL, refreshed by opencode /models and setup model listing; chat dispatch reads the cache only and never blocks on the fetch. NULLRAY_MODELSDEV=0 disables it. The same cache enriches /models output (context limit, per-Mtok cost) for any provider models.dev knows.
- The /messages surface takes x-api-key auth (not Bearer); chat/completions and models take Bearer. Both carry x-opencode-session.
- Chat, stream, and models requests send `x-opencode-session` with the live session name (process fallback when unset). Required for Go routing and cache affinity.
- gpt-*, grok-*, muse-* (Responses API), gemini-* (Google surface), and jev-* (systemone) get a clear unsupported-surface error. A custom NULLRAY_BASE_URL skips model routing so proxies can normalize; a protocol rejection there gets a hint error.
- No /embeddings on Zen: both opencode providers report embed=nil so RAG falls back to a local or OpenRouter embedder.
- NULLRAY_PROVIDER=zen aliases to opencode.
- HTTP User-Agent is `nullray/<VERSION>`.

Anthropic notes:

- The anthropic provider posts to /v1/messages (x-api-key, anthropic-version) instead of chat/completions, which api.anthropic.com never served.
- /reasoning effort maps to a thinking budget_tokens floor; temperature/top_p are dropped while thinking is on.
- /models still uses the OpenAI-shape GET /v1/models.

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
- llamacpp probes LLAMA_CPP_HOST first; when unset it tries the classic 8080 default and the newer 9931 default, and adopts whichever answers (including for explicit NULLRAY_PROVIDER=llamacpp).
- LLAMA_CPP_API_KEY and LM_API_TOKEN are scrubbed from the process environment but still reach their providers through the pre-scrub key cache. LLAMA_CPP_HOST and LM_STUDIO_HOST stay in env.
- Under NULLRAY_SANDBOX_NET=local the TCP connect allowlist covers 443, 80, and the default local ports (11434, 1234, 8080, 9931) plus any port parsed from a configured provider host URL (OLLAMA_HOST, LM_STUDIO_HOST, LLAMA_CPP_HOST, NULLRAY_BASE_URL, OPENAI_BASE_URL). NULLRAY_SANDBOX_PORTS=a,b adds more.
- NULLRAY_HTTP_TIMEOUT (seconds) overrides the 120s chat timeout; raise it for slow CPU inference.
- NULLRAY_PROMPT=tiny shrinks the system prompt to the core tool set (about 700 tokens vs 10k) for small models; auto resolves to tiny whenever the active provider is local. Use lean or full when the local model is large.
- NULLRAY_JSON_MODE=1 sends response_format json_object when tools are off (llama.cpp enforces it via grammar, OpenAI and OpenRouter honor it). NULLRAY_JSON_SCHEMA=<schema JSON> sends a json_schema response_format for strict structured output.
- NULLRAY_JUDGE adds a post-run completion judge: jev calls a System One decision API (zen /v1/systemone by default, model jev-1.13), laya points the same API at a local laya-serve on 127.0.0.1:8000, chat scores via the active provider's chat model, and auto picks jev when a key exists else chat on a local provider. Suffix :MODEL@URL overrides model and endpoint. NULLRAY_JUDGE_KEY sets the key, NULLRAY_JUDGE_CONFIDENCE the pass threshold (default 0.7). A low score marks the run judge_fail and --print-strict exits nonzero. NULLRAY_JUDGE_RETRY=1 escalates a failed run through NULLRAY_PROVIDER_FALLBACKS: the session is nudged and continued on each fallback provider until the judge passes. Judges see the agent's claims, not the filesystem, so pair with NULLRAY_VERIFY for outcome checks.
- Function-calling specialist models (Salesforce xLAM-1b-fc-r and similar) only emit correct calls through their trained prompt format; llama.cpp's generic chat template ignores the tools field for them (supports_tools=false in /props). A custom --chat-template-file can wire the format up, but general instruct models (Qwen2.5/3, Granite) are the easier local pick. ibm-granite/granite-4.1-3b-GGUF reports supports_tools=true in /props and bench-tested at 4/10 on a 3B budget, a modest step over Qwen2.5-1.5B at 3/10.
- llama-server defaults to a small context (4096); nullray's system prompt needs more. Start it with --ctx-size 16384 or larger. A prompt-too-large 400 now shows the server message plus a --ctx-size hint.
- Embeddings: POST {base}/embeddings (encoding_format float). Ollama falls back to native POST /api/embed on 404.
- NULLRAY_EMBED_PROVIDER / NULLRAY_EMBED_MODEL override the chat provider for vectors. Defaults: ollama nomic-embed-text, openrouter openai/text-embedding-3-small, openai text-embedding-3-small. lmstudio and llamacpp require NULLRAY_EMBED_MODEL.
- NULLRAY_RAG=auto|1|0 (default auto). Index under .nullray/rag/. NULLRAY_RAG_ARTIFACTS=0 skips artifact indexing. rag_reindex rebuilds memory and retained artifacts.
- NULLRAY_RAG_CODE=1 opts into a live-tree lane: rag_reindex scope=code indexes source/text files under the workspace (denylist dirs, 800 file and 4MB total caps, 200KB per file, secret-screened). rag_query scope=code restricts hits. Hits flag files changed since indexing.
- Embed privacy: cloud embed providers receive indexed text even when chat is local. Prefer a local embed model (nomic) when ZDR or offline matter. Do not index the live codebase; use grep/locate for source.

Media attachments:

- User messages can carry image (image_url), audio (input_audio), and video (video_url) parts as base64 data URIs. Serialized in provider/openai_request.odin write_media_content_json; gating hints in provider/media.odin media_kind_supported (advisory only).
- Attach via /attach PATH in the TUI or --image/--audio/--video/--media in print mode. NULLRAY_MEDIA=0 disables, NULLRAY_MEDIA_MAX caps bytes, NULLRAY_MEDIA_TURNS limits how many past user turns resend payloads.
- Verified on OpenCode Zen chat/completions: qwen3.x and minimax-m3 accept image_url; qwen3.x-plus accepts video_url. Zen free-tier and most claude/gpt/gemini ids reject /chat/completions entirely (ModelProtocolUnsupported), so media tests need qwen/minimax-class models.

Source of truth: nullray/constants/constants.odin and nullray/provider/builtins.odin.

Cache discipline (Anthropic/OpenRouter prefix caching):

- Provider Usage carries cache_read_tokens and cache_write_tokens (usage.jsonl cache_read/cache_write, /usage cache_read percent).
- The request prefix must stay byte-stable to hit cache. System prompt is built once per session, no timestamps. Tool order is registry insertion order, deterministic.
- search_tools deferred activation un-filters tools at their registry positions mid-session, which breaks the tools prefix from the first newly included tool onward. Keep activations rare and early.
